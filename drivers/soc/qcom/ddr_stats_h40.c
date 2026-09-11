// SPDX-License-Identifier: GPL-2.0-only
/*
 * OnePlus H.40 / Qualcomm AOP H.O.1.1 DDR transition decoder
 *
 * H.O.1.1 publishes a bounded transition ring, not the magic-tagged
 * cumulative table used by the newer qcom,ddr-stats ABI.  Keep the two
 * protocols separate so an H.O.1.1 page can never be mistaken for H.O.2.0
 * residency data.
 */

#define pr_fmt(fmt) "%s: " fmt, __func__

#include <linux/err.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/platform_device.h>
#include <linux/sizes.h>
#include <linux/slab.h>
#include <linux/sort.h>
#include <linux/soc/qcom/smem.h>
#include <linux/types.h>

#define H40_DDR_PAGE_SIZE		SZ_1K
#define H40_DDR_EVENT_OFFSET		0x10
#define H40_DDR_EVENT_COUNT		50
#define H40_DDR_CONFIG_OFFSET		0x330
#define H40_DDR_STATS_OFFSET		0x350
#define H40_DDR_SMEM_ITEM		604
#define H40_DDR_SMEM_MAJOR		1
#define H40_DDR_SMEM_MINOR		0
#define H40_DDR_MAX_PLANS		16
#define H40_AOP_TICKS_PER_MSEC		19200ULL
#define H40_AOP_SMEM_TABLE_OFFSET	0xe0000
#define H40_AOP_SMEM_TABLE_ENTRIES	10
#define H40_DDR_SMEM_WINDOW		SZ_4K
#define H40_DDR_HEADER_DUMP_SIZE	32

enum h40_ddr_event_type {
	H40_DDR_FREQ_CHANGE,
	H40_DDR_FREQ_FLUSH,
	H40_DDR_FREQ_DONE,
};

struct h40_ddr_dictionary {
	__le32 event_offset;
	__le32 event_count;
	__le32 stats_offset;
	__le32 config_offset;
};

struct h40_ddr_event {
	__le64 timestamp;
	u8 event;
	u8 powerstate_request;
	u8 bcm_acv;
	u8 bcm_alc;
	u8 bcm_mc_reg_mc;
	u8 bcm_shub_reg_shub;
	u8 next_mc_current_mc;
	u8 next_shub_current_shub;
};

struct h40_ddr_aggregate {
	__le32 mc_count;
	__le32 shub_count;
	__le32 restore_count;
	__le32 collapse_count;
	__le64 mc_cp_history;
	__le64 shub_cp_history;
	__le64 mc_begin;
	__le64 shub_begin;
	__le64 previous_mc_begin;
	__le64 previous_shub_begin;
	__le64 collapse_begin;
	__le64 restore_begin;
	__le64 mc_max;
	__le64 mc_max_time;
	__le64 shub_max;
	__le64 shub_max_time;
	__le64 collapse_max;
	__le64 collapse_max_time;
	__le64 restore_max;
	__le64 restore_max_time;
	__le32 flush_count;
	__le32 pad;
	__le64 flush_begin;
	__le64 flush_max;
	__le64 flush_max_time;
};

struct h40_ddr_smem_table {
	__le16 size;
	__le16 offset;
};

struct h40_ddr_smem_header {
	__le16 major;
	__le16 minor;
	struct h40_ddr_smem_table table[4];
};

struct h40_aop_smem_addr {
	__le32 item;
	__le32 phys_addr;
};

struct h40_aop_smem_table {
	__le32 initialized;
	__le32 count;
	struct h40_aop_smem_addr entry[H40_AOP_SMEM_TABLE_ENTRIES];
};

/* Explicit padding preserves the 40-byte H.O.1.1 FREQ_STATE ABI. */
struct h40_ddr_freq_state {
	u8 clk_idx;
	u8 reserved0[3];
	__le32 freq_khz;
	__le32 clk_period;
	u8 enabled;
	u8 reserved1[3];
	__le32 mode;
	__le32 vddcx;
	__le32 vddmx;
	__le32 vdda;
	__le32 pmic_mode;
	u8 max_up_idx;
	u8 min_down_idx;
	u8 double_switch;
	u8 reserved2;
};

struct h40_ddr_data {
	void __iomem *page;
	struct kobject *kobj;
	struct kobj_attribute abi_attr;
	struct kobj_attribute transitions_attr;
	struct kobj_attribute recent_residency_attr;
	struct kobj_attribute manager_stats_attr;
	struct kobj_attribute clock_plans_attr;
	u32 mc_freq_khz[H40_DDR_MAX_PLANS];
	u32 shub_freq_khz[H40_DDR_MAX_PLANS];
	u8 mc_count;
	u8 shub_count;
	const char *clock_plan_source;
	const char *clock_plan_version;
	int qcom_smem_status;
	int aop_smem_status;
	phys_addr_t clock_plan_phys;
	size_t qcom_smem_size;
	u8 qcom_header[H40_DDR_HEADER_DUMP_SIZE];
	u8 qcom_header_size;
	u8 aop_header[H40_DDR_HEADER_DUMP_SIZE];
	u8 aop_header_size;
};

static int h40_ddr_validate_page(const u8 *page)
{
	const struct h40_ddr_dictionary *dict = (const void *)page;

	if (le32_to_cpu(dict->event_offset) != H40_DDR_EVENT_OFFSET ||
	    le32_to_cpu(dict->event_count) != H40_DDR_EVENT_COUNT ||
	    le32_to_cpu(dict->stats_offset) != H40_DDR_STATS_OFFSET ||
	    le32_to_cpu(dict->config_offset) != H40_DDR_CONFIG_OFFSET)
		return -EINVAL;

	return 0;
}

static int h40_ddr_snapshot(struct h40_ddr_data *data, u8 *page)
{
	u8 *check;
	int attempt;
	int ret = -EAGAIN;

	check = kmalloc(H40_DDR_PAGE_SIZE, GFP_KERNEL);
	if (!check)
		return -ENOMEM;

	for (attempt = 0; attempt < 5; attempt++) {
		memcpy_fromio(page, data->page, H40_DDR_PAGE_SIZE);
		rmb();
		memcpy_fromio(check, data->page, H40_DDR_PAGE_SIZE);
		if (!memcmp(page, check, H40_DDR_PAGE_SIZE)) {
			ret = h40_ddr_validate_page(page);
			break;
		}
	}

	kfree(check);
	return ret;
}

static int h40_ddr_event_compare(const void *left, const void *right)
{
	const struct h40_ddr_event *a = left;
	const struct h40_ddr_event *b = right;
	u64 a_time = le64_to_cpu(a->timestamp);
	u64 b_time = le64_to_cpu(b->timestamp);

	if (a_time < b_time)
		return -1;
	if (a_time > b_time)
		return 1;
	return 0;
}

static struct h40_ddr_event *h40_ddr_sorted_events(const u8 *page)
{
	struct h40_ddr_event *events;

	events = kmemdup(page + H40_DDR_EVENT_OFFSET,
			  sizeof(*events) * H40_DDR_EVENT_COUNT, GFP_KERNEL);
	if (!events)
		return NULL;

	sort(events, H40_DDR_EVENT_COUNT, sizeof(*events),
	     h40_ddr_event_compare, NULL);
	return events;
}

static ssize_t h40_ddr_abi_show(struct kobject *kobj,
				struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "aop-ho1.1-transition-ring\n");
}

static ssize_t h40_ddr_transitions_show(struct kobject *kobj,
					struct kobj_attribute *attr, char *buf)
{
	struct h40_ddr_data *data = container_of(attr, struct h40_ddr_data,
						 transitions_attr);
	struct h40_ddr_event *events;
	u8 *page;
	ssize_t length = 0;
	int ret;
	int i;

	page = kmalloc(H40_DDR_PAGE_SIZE, GFP_KERNEL);
	if (!page)
		return -ENOMEM;
	ret = h40_ddr_snapshot(data, page);
	if (ret)
		goto out_page;

	events = h40_ddr_sorted_events(page);
	if (!events) {
		ret = -ENOMEM;
		goto out_page;
	}

	length += scnprintf(buf + length, PAGE_SIZE - length,
		"ticks event pwr acv/alc mcreq shreq mccp shcp mc_khz shub_khz\n");
	for (i = 0; i < H40_DDR_EVENT_COUNT; i++) {
		const struct h40_ddr_event *event = &events[i];
		u64 timestamp = le64_to_cpu(event->timestamp);
		u8 current_mc;
		u8 current_shub;
		u32 mc_khz = 0;
		u32 shub_khz = 0;

		if (!timestamp || event->event > H40_DDR_FREQ_DONE)
			continue;
		current_mc = event->next_mc_current_mc & 0xf;
		current_shub = event->next_shub_current_shub & 0xf;
		if (current_mc < data->mc_count)
			mc_khz = data->mc_freq_khz[current_mc];
		if (current_shub < data->shub_count)
			shub_khz = data->shub_freq_khz[current_shub];
		length += scnprintf(buf + length, PAGE_SIZE - length,
			"%016llx %u %02x %02x/%02x %x/%x %x/%x %x/%x %x/%x %u %u\n",
			timestamp, event->event, event->powerstate_request,
			event->bcm_acv, event->bcm_alc,
			event->bcm_mc_reg_mc >> 4,
			event->bcm_mc_reg_mc & 0xf,
			event->bcm_shub_reg_shub >> 4,
			event->bcm_shub_reg_shub & 0xf,
			event->next_mc_current_mc >> 4, current_mc,
			event->next_shub_current_shub >> 4, current_shub,
			mc_khz, shub_khz);
		if (PAGE_SIZE - length < 96)
			break;
	}

	kfree(events);
	kfree(page);
	return length;

out_page:
	kfree(page);
	return ret;
}

static ssize_t h40_ddr_recent_residency_show(struct kobject *kobj,
					     struct kobj_attribute *attr,
					     char *buf)
{
	struct h40_ddr_data *data = container_of(attr, struct h40_ddr_data,
						 recent_residency_attr);
	struct h40_ddr_event *events;
	u64 ticks[H40_DDR_MAX_PLANS] = { 0 };
	u32 intervals[H40_DDR_MAX_PLANS] = { 0 };
	const struct h40_ddr_event *previous = NULL;
	u8 *page;
	ssize_t length = 0;
	int ret;
	int i;

	page = kmalloc(H40_DDR_PAGE_SIZE, GFP_KERNEL);
	if (!page)
		return -ENOMEM;
	ret = h40_ddr_snapshot(data, page);
	if (ret)
		goto out_page;
	events = h40_ddr_sorted_events(page);
	if (!events) {
		ret = -ENOMEM;
		goto out_page;
	}

	for (i = 0; i < H40_DDR_EVENT_COUNT; i++) {
		const struct h40_ddr_event *event = &events[i];
		u64 timestamp = le64_to_cpu(event->timestamp);

		if (!timestamp || event->event != H40_DDR_FREQ_DONE)
			continue;
		if (previous) {
			u64 previous_time = le64_to_cpu(previous->timestamp);
			u8 cp = previous->next_mc_current_mc & 0xf;

			if (cp < H40_DDR_MAX_PLANS && timestamp > previous_time) {
				ticks[cp] += timestamp - previous_time;
				intervals[cp]++;
			}
		}
		previous = event;
	}

	length += scnprintf(buf + length, PAGE_SIZE - length,
		"window=completed intervals inside last 50 AOP events; not lifetime totals\n");
	for (i = 0; i < H40_DDR_MAX_PLANS; i++) {
		if (!intervals[i])
			continue;
		length += scnprintf(buf + length, PAGE_SIZE - length,
			"MC CP:%d Freq:%uKHz intervals:%u Time:%llums\n",
			i, i < data->mc_count ? data->mc_freq_khz[i] : 0,
			intervals[i], ticks[i] / H40_AOP_TICKS_PER_MSEC);
	}

	kfree(events);
	kfree(page);
	return length;

out_page:
	kfree(page);
	return ret;
}

static ssize_t h40_ddr_manager_stats_show(struct kobject *kobj,
					  struct kobj_attribute *attr,
					  char *buf)
{
	struct h40_ddr_data *data = container_of(attr, struct h40_ddr_data,
						 manager_stats_attr);
	const struct h40_ddr_aggregate *stats;
	u8 *page;
	ssize_t length;
	int ret;

	page = kmalloc(H40_DDR_PAGE_SIZE, GFP_KERNEL);
	if (!page)
		return -ENOMEM;
	ret = h40_ddr_snapshot(data, page);
	if (ret) {
		kfree(page);
		return ret;
	}
	stats = (const void *)(page + H40_DDR_STATS_OFFSET);
	length = scnprintf(buf, PAGE_SIZE,
		"mc_count=%u\nshub_count=%u\nrestore_count=%u\n"
		"collapse_count=%u\nflush_count=%u\n"
		"mc_cp_history=%016llx\nshub_cp_history=%016llx\n"
		"mc_max_ticks=%llu\nshub_max_ticks=%llu\n"
		"collapse_max_ticks=%llu\nrestore_max_ticks=%llu\n"
		"flush_max_ticks=%llu\n",
		le32_to_cpu(stats->mc_count), le32_to_cpu(stats->shub_count),
		le32_to_cpu(stats->restore_count),
		le32_to_cpu(stats->collapse_count),
		le32_to_cpu(stats->flush_count),
		le64_to_cpu(stats->mc_cp_history),
		le64_to_cpu(stats->shub_cp_history),
		le64_to_cpu(stats->mc_max), le64_to_cpu(stats->shub_max),
		le64_to_cpu(stats->collapse_max),
		le64_to_cpu(stats->restore_max), le64_to_cpu(stats->flush_max));
	kfree(page);
	return length;
}

static ssize_t h40_ddr_clock_plans_show(struct kobject *kobj,
					struct kobj_attribute *attr, char *buf)
{
	struct h40_ddr_data *data = container_of(attr, struct h40_ddr_data,
						 clock_plans_attr);
	ssize_t length = 0;
	int i;

	length += scnprintf(buf + length, PAGE_SIZE - length,
		"source=%s version=%s qcom_status=%d qcom_size=%zu "
		"aop_table_status=%d item_phys=%pa\n",
		data->clock_plan_source, data->clock_plan_version,
		data->qcom_smem_status, data->qcom_smem_size,
		data->aop_smem_status, &data->clock_plan_phys);
	length += scnprintf(buf + length, PAGE_SIZE - length, "qcom_header=");
	for (i = 0; i < data->qcom_header_size; i++)
		length += scnprintf(buf + length, PAGE_SIZE - length, "%02x",
					data->qcom_header[i]);
	length += scnprintf(buf + length, PAGE_SIZE - length, "\naop_header=");
	for (i = 0; i < data->aop_header_size; i++)
		length += scnprintf(buf + length, PAGE_SIZE - length, "%02x",
					data->aop_header[i]);
	length += scnprintf(buf + length, PAGE_SIZE - length, "\n");
	for (i = 0; i < data->mc_count; i++)
		length += scnprintf(buf + length, PAGE_SIZE - length,
			"MC CP:%d Freq:%uKHz\n", i, data->mc_freq_khz[i]);
	for (i = 0; i < data->shub_count; i++)
		length += scnprintf(buf + length, PAGE_SIZE - length,
			"SHUB CP:%d Freq:%uKHz\n", i, data->shub_freq_khz[i]);
	return length;
}

static void h40_ddr_capture_header(u8 *destination, u8 *destination_size,
				    const u8 *smem, size_t size)
{
	size_t length = min_t(size_t, size, H40_DDR_HEADER_DUMP_SIZE);

	memcpy(destination, smem, length);
	*destination_size = length;
}

static int h40_ddr_parse_version(const u8 *smem, size_t size,
				 const char **version)
{
	const struct h40_ddr_smem_header *header;
	__le32 raw_version;
	u32 packed_version;

	if (size < sizeof(*header))
		return -EINVAL;

	header = (const void *)smem;
	if (le16_to_cpu(header->major) == H40_DDR_SMEM_MAJOR &&
	    le16_to_cpu(header->minor) == H40_DDR_SMEM_MINOR) {
		*version = "split-u16-1.0";
		return 0;
	}

	/*
	 * Some Qualcomm XBL/DDRSS producers encode the same 1.0 version as
	 * one 16.16 word.  The table headers still begin at byte four, so only
	 * the version interpretation differs from ddr_smem_info.
	 */
	memcpy(&raw_version, smem, sizeof(raw_version));
	packed_version = le32_to_cpu(raw_version);
	if (packed_version == (H40_DDR_SMEM_MAJOR << 16 |
			       H40_DDR_SMEM_MINOR)) {
		*version = "packed-16.16-1.0";
		return 0;
	}

	return -EPROTONOSUPPORT;
}

static int h40_ddr_load_one_plan(const u8 *smem, size_t smem_size,
				 const struct h40_ddr_smem_table *table,
				 u32 *frequencies, u8 *count)
{
	const struct h40_ddr_freq_state *states;
	u16 offset = le16_to_cpu(table->offset);
	u16 size = le16_to_cpu(table->size);
	int i;

	if (!size || size % sizeof(*states) ||
	    size > H40_DDR_MAX_PLANS * sizeof(*states) ||
	    offset > smem_size || size > smem_size - offset)
		return -EINVAL;

	states = (const void *)(smem + offset);
	*count = size / sizeof(*states);
	for (i = 0; i < *count; i++)
		frequencies[i] = le32_to_cpu(states[i].freq_khz);
	return 0;
}

static int h40_ddr_parse_clock_plans(struct h40_ddr_data *data,
				      const u8 *smem, size_t size)
{
	const struct h40_ddr_smem_header *header;
	int ret;

	data->mc_count = 0;
	data->shub_count = 0;
	ret = h40_ddr_parse_version(smem, size, &data->clock_plan_version);
	if (ret)
		return ret;
	header = (const void *)smem;

	ret = h40_ddr_load_one_plan(smem, size, &header->table[0],
				     data->mc_freq_khz, &data->mc_count);
	if (ret)
		return ret;
	return h40_ddr_load_one_plan(smem, size, &header->table[1],
				      data->shub_freq_khz, &data->shub_count);
}

static int h40_ddr_load_clock_plans_from_aop(struct h40_ddr_data *data,
					     const struct resource *base)
{
	struct h40_aop_smem_table table;
	struct device_node *smem_np, *region_np;
	struct resource smem_region;
	void __iomem *table_io, *item_io;
	resource_size_t item_phys = 0;
	u8 *snapshot;
	u32 count;
	int i, ret;

	if (H40_AOP_SMEM_TABLE_OFFSET > resource_size(base) ||
	    sizeof(table) > resource_size(base) - H40_AOP_SMEM_TABLE_OFFSET)
		return -ERANGE;

	table_io = ioremap_nocache(base->start + H40_AOP_SMEM_TABLE_OFFSET,
				    sizeof(table));
	if (!table_io)
		return -ENOMEM;
	memcpy_fromio(&table, table_io, sizeof(table));
	iounmap(table_io);

	if (le32_to_cpu(table.initialized) != 1)
		return -ENODATA;
	count = le32_to_cpu(table.count);
	if (!count || count > ARRAY_SIZE(table.entry))
		return -EPROTO;
	for (i = 0; i < count; i++) {
		if (le32_to_cpu(table.entry[i].item) == H40_DDR_SMEM_ITEM) {
			item_phys = le32_to_cpu(table.entry[i].phys_addr);
			data->clock_plan_phys = item_phys;
			break;
		}
	}
	if (!item_phys)
		return -ENOENT;

	smem_np = of_find_compatible_node(NULL, NULL, "qcom,smem");
	if (!smem_np)
		return -ENODEV;
	region_np = of_parse_phandle(smem_np, "memory-region", 0);
	of_node_put(smem_np);
	if (!region_np)
		return -ENODEV;
	ret = of_address_to_resource(region_np, 0, &smem_region);
	of_node_put(region_np);
	if (ret)
		return ret;
	if (item_phys < smem_region.start || item_phys > smem_region.end ||
	    H40_DDR_SMEM_WINDOW - 1 > smem_region.end - item_phys)
		return -ERANGE;

	item_io = ioremap_nocache(item_phys, H40_DDR_SMEM_WINDOW);
	if (!item_io)
		return -ENOMEM;
	snapshot = kmalloc(H40_DDR_SMEM_WINDOW, GFP_KERNEL);
	if (!snapshot) {
		iounmap(item_io);
		return -ENOMEM;
	}
	memcpy_fromio(snapshot, item_io, H40_DDR_SMEM_WINDOW);
	iounmap(item_io);
	h40_ddr_capture_header(data->aop_header, &data->aop_header_size,
			       snapshot, H40_DDR_SMEM_WINDOW);

	ret = h40_ddr_parse_clock_plans(data, snapshot,
					 H40_DDR_SMEM_WINDOW);
	kfree(snapshot);
	return ret;
}

static int h40_ddr_load_clock_plans(struct h40_ddr_data *data,
				     const struct resource *base)
{
	const u8 *smem;
	size_t size = 0;
	int ret;

	data->clock_plan_source = "unavailable";
	data->clock_plan_version = "unrecognized";
	smem = qcom_smem_get(QCOM_SMEM_HOST_ANY, H40_DDR_SMEM_ITEM, &size);
	if (IS_ERR(smem))
		ret = PTR_ERR(smem);
	else {
		data->qcom_smem_size = size;
		h40_ddr_capture_header(data->qcom_header,
				       &data->qcom_header_size, smem, size);
		ret = h40_ddr_parse_clock_plans(data, smem, size);
	}
	data->qcom_smem_status = ret;
	if (!ret) {
		data->clock_plan_source = "qcom_smem";
		return 0;
	}
	if (ret == -EPROBE_DEFER)
		return ret;

	ret = h40_ddr_load_clock_plans_from_aop(data, base);
	data->aop_smem_status = ret;
	if (!ret)
		data->clock_plan_source = "aop_xbl_address_table";
	return ret;
}

static int h40_ddr_create_attr(struct kobject *kobj,
				struct kobj_attribute *attr, const char *name,
				ssize_t (*show)(struct kobject *,
						struct kobj_attribute *, char *))
{
	sysfs_attr_init(&attr->attr);
	attr->attr.name = name;
	attr->attr.mode = 0444;
	attr->show = show;
	return sysfs_create_file(kobj, &attr->attr);
}

static int h40_ddr_stats_probe(struct platform_device *pdev)
{
	struct h40_ddr_data *data;
	struct resource *base;
	struct resource *offset;
	void __iomem *pointer;
	resource_size_t base_size;
	u32 page_offset;
	u8 *snapshot;
	int ret;

	BUILD_BUG_ON(sizeof(struct h40_ddr_event) != 16);
	BUILD_BUG_ON(sizeof(struct h40_ddr_aggregate) != 0xb0);
	BUILD_BUG_ON(sizeof(struct h40_ddr_freq_state) != 0x28);
	BUILD_BUG_ON(sizeof(struct h40_aop_smem_addr) != 8);
	BUILD_BUG_ON(sizeof(struct h40_aop_smem_table) != 88);

	data = devm_kzalloc(&pdev->dev, sizeof(*data), GFP_KERNEL);
	if (!data)
		return -ENOMEM;
	base = platform_get_resource_byname(pdev, IORESOURCE_MEM,
					    "phys_addr_base");
	offset = platform_get_resource_byname(pdev, IORESOURCE_MEM,
					      "offset_addr");
	if (!base || !offset)
		return -ENODEV;

	pointer = ioremap_nocache(offset->start, SZ_4);
	if (!pointer)
		return -ENOMEM;
	page_offset = readl_relaxed(pointer);
	iounmap(pointer);

	base_size = resource_size(base);
	if (!page_offset || page_offset & (H40_DDR_PAGE_SIZE - 1) ||
	    page_offset > base_size || H40_DDR_PAGE_SIZE > base_size - page_offset) {
		dev_err(&pdev->dev, "invalid H.O.1.1 DDR page offset %#x\n",
			page_offset);
		return -EINVAL;
	}
	data->page = devm_ioremap_nocache(&pdev->dev,
					   base->start + page_offset,
					   H40_DDR_PAGE_SIZE);
	if (!data->page)
		return -ENOMEM;

	snapshot = kmalloc(H40_DDR_PAGE_SIZE, GFP_KERNEL);
	if (!snapshot)
		return -ENOMEM;
	ret = h40_ddr_snapshot(data, snapshot);
	kfree(snapshot);
	if (ret) {
		dev_err(&pdev->dev, "invalid or unstable H.O.1.1 DDR dictionary\n");
		return ret;
	}

	ret = h40_ddr_load_clock_plans(data, base);
	if (ret == -EPROBE_DEFER)
		return ret;
	if (ret)
		dev_warn(&pdev->dev,
			 "SMEM 604 clock plans unavailable (qcom=%d, AOP table=%d); exposing CP indices\n",
			 data->qcom_smem_status, data->aop_smem_status);

	data->kobj = kobject_create_and_add("ddr", power_kobj);
	if (!data->kobj)
		return -ENOMEM;
	ret = h40_ddr_create_attr(data->kobj, &data->abi_attr, "abi",
				  h40_ddr_abi_show);
	if (ret)
		goto err_kobj;
	ret = h40_ddr_create_attr(data->kobj, &data->transitions_attr,
				  "transitions", h40_ddr_transitions_show);
	if (ret)
		goto err_abi;
	ret = h40_ddr_create_attr(data->kobj, &data->recent_residency_attr,
				  "recent_residency",
				  h40_ddr_recent_residency_show);
	if (ret)
		goto err_transitions;
	ret = h40_ddr_create_attr(data->kobj, &data->manager_stats_attr,
				  "manager_stats", h40_ddr_manager_stats_show);
	if (ret)
		goto err_recent;
	ret = h40_ddr_create_attr(data->kobj, &data->clock_plans_attr,
				  "clock_plans", h40_ddr_clock_plans_show);
	if (ret)
		goto err_manager;

	platform_set_drvdata(pdev, data);
	dev_info(&pdev->dev,
		 "H.O.1.1 DDR ring ready at %pa+%#x, MC plans=%u SHUB plans=%u source=%s\n",
		 &base->start, page_offset, data->mc_count, data->shub_count,
		 data->clock_plan_source);
	return 0;

err_manager:
	sysfs_remove_file(data->kobj, &data->manager_stats_attr.attr);
err_recent:
	sysfs_remove_file(data->kobj, &data->recent_residency_attr.attr);
err_transitions:
	sysfs_remove_file(data->kobj, &data->transitions_attr.attr);
err_abi:
	sysfs_remove_file(data->kobj, &data->abi_attr.attr);
err_kobj:
	kobject_put(data->kobj);
	return ret;
}

static int h40_ddr_stats_remove(struct platform_device *pdev)
{
	struct h40_ddr_data *data = platform_get_drvdata(pdev);

	if (!data)
		return 0;
	sysfs_remove_file(data->kobj, &data->clock_plans_attr.attr);
	sysfs_remove_file(data->kobj, &data->manager_stats_attr.attr);
	sysfs_remove_file(data->kobj, &data->recent_residency_attr.attr);
	sysfs_remove_file(data->kobj, &data->transitions_attr.attr);
	sysfs_remove_file(data->kobj, &data->abi_attr.attr);
	kobject_put(data->kobj);
	platform_set_drvdata(pdev, NULL);
	return 0;
}

static const struct of_device_id h40_ddr_stats_of_match[] = {
	{ .compatible = "qcom,h40-ddr-stats" },
	{ }
};
MODULE_DEVICE_TABLE(of, h40_ddr_stats_of_match);

static struct platform_driver h40_ddr_stats_driver = {
	.probe = h40_ddr_stats_probe,
	.remove = h40_ddr_stats_remove,
	.driver = {
		.name = "h40_ddr_stats",
		.of_match_table = h40_ddr_stats_of_match,
	},
};
module_platform_driver(h40_ddr_stats_driver);

MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("Qualcomm AOP H.O.1.1 DDR transition decoder");
