<script setup>
import { h, onMounted, ref } from 'vue'
import { NDatePicker, NInput, NSelect, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate } from '@/utils'

defineOptions({ name: '手续费账单' })

const $table = ref(null)
const queryItems = ref({
  biz_type: null,
  status: null,
  user_id: '',
  record_id: '',
  start_time: null,
  end_time: null,
})
const datetimeRange = ref(null)

onMounted(() => {
  $table.value?.handleSearch()
})

const bizTypeOptions = [
  { label: '通话', value: 'call' },
  { label: '礼物', value: 'gift' },
]

const statusOptions = [
  { label: '全额扣成', value: 'charged_full' },
  { label: '部分扣成', value: 'charged_partial' },
  { label: '余额不足未扣', value: 'skipped_insufficient' },
  { label: '已扣成', value: 'charged' },
]

const statusMap = {
  charged_full: { text: '全额扣成', type: 'success' },
  charged_partial: { text: '部分扣成', type: 'warning' },
  skipped_insufficient: { text: '余额不足未扣', type: 'error' },
  charged: { text: '已扣成', type: 'success' },
}

function statusTag(status) {
  if (!status) return '-'
  const target = statusMap[status] || { text: status, type: 'default' }
  return h(NTag, { type: target.type, bordered: false }, { default: () => target.text })
}

function userText(user) {
  if (!user?.id) return '-'
  return `ID:${user.id} ${user.nickname || user.phone || ''}`.trim()
}

function formatMoney(value, unit) {
  const n = Number(value || 0)
  return `${n.toFixed(2)}${unit}`
}

function formatRate(row) {
  const bps = Number(row.rate_bps || 0)
  if (!Number.isFinite(bps) || bps <= 0) return '-'
  return `${(bps / 100).toFixed(2)}%`
}

function formatTime(value) {
  return value ? formatDate(value, 'YYYY-MM-DD HH:mm:ss') : '-'
}

function formatTimestamp(timestamp) {
  return formatDate(new Date(timestamp), 'YYYY-MM-DD HH:mm:ss')
}

function handleDateRangeChange(value) {
  datetimeRange.value = value
  if (!value) {
    queryItems.value.start_time = null
    queryItems.value.end_time = null
    return
  }
  queryItems.value.start_time = formatTimestamp(value[0])
  queryItems.value.end_time = formatTimestamp(value[1])
}

const columns = [
  {
    title: '业务',
    key: 'biz_type',
    width: 90,
    align: 'center',
    render(row) {
      const text = row.biz_type === 'call' ? '通话' : '礼物'
      return h(
        NTag,
        { type: row.biz_type === 'call' ? 'info' : 'success', bordered: false },
        { default: () => text }
      )
    },
  },
  { title: '记录ID', key: 'record_id', width: 90, align: 'center' },
  {
    title: '业务信息',
    key: 'biz_info',
    minWidth: 260,
    render(row) {
      if (row.biz_type === 'call') {
        return h('div', { class: 'meta-wrap' }, [
          h('div', {}, `主叫：${userText(row.caller)}`),
          h('div', {}, `被叫：${userText(row.callee)}`),
          h('div', { class: 'sub' }, `通话单价：${row.call_price || 0}金币/分钟`),
        ])
      }
      return h('div', { class: 'meta-wrap' }, [
        h('div', {}, `送礼方：${userText(row.sender)}`),
        h('div', {}, `收礼方：${userText(row.receiver)}`),
        h('div', { class: 'sub' }, `${row.gift_name || '-'} / ${row.gift_unit_price || 0}金币`),
      ])
    },
  },
  {
    title: '规则快照',
    key: 'rule',
    width: 210,
    render(row) {
      if (row.biz_type === 'call') {
        return h('div', { class: 'meta-wrap' }, [
          h('div', {}, `阈值：${row.threshold_minutes || 0}分钟`),
          h('div', {}, `费率：${formatRate(row)}`),
          h('div', { class: 'sub' }, `已处理：${row.processed_chargeable_minutes || 0}分钟`),
        ])
      }
      return h('div', { class: 'meta-wrap' }, [
        h('div', {}, `阈值：${row.threshold_coins || 0}金币`),
        h('div', {}, `费率：${formatRate(row)}`),
      ])
    },
  },
  {
    title: '付费/送礼方手续费',
    key: 'payer_fee',
    width: 250,
    render(row) {
      if (row.biz_type === 'call') {
        return h('div', { class: 'meta-wrap' }, [
          h('div', {}, `付费方：${userText(row.payer_user)}`),
          h('div', {}, `理论：${formatMoney(row.payer_expected_coins, '金币')}`),
          h('div', {}, `实扣：${formatMoney(row.payer_actual_coins, '金币')}`),
          h('div', {}, ['状态：', statusTag(row.payer_status)]),
        ])
      }
      return h('div', { class: 'meta-wrap' }, [
        h('div', {}, `理论：${formatMoney(row.sender_expected_coins, '金币')}`),
        h('div', {}, `实扣：${formatMoney(row.sender_actual_coins, '金币')}`),
        h('div', {}, ['状态：', statusTag(row.sender_status)]),
      ])
    },
  },
  {
    title: '收益方手续费',
    key: 'income_fee',
    width: 230,
    render(row) {
      if (row.biz_type !== 'call') return '-'
      return h('div', { class: 'meta-wrap' }, [
        h('div', {}, `收益方：${userText(row.income_user)}`),
        h('div', {}, `理论：${formatMoney(row.income_expected_diamonds, '钻石')}`),
        h('div', {}, `实扣：${formatMoney(row.income_actual_diamonds, '钻石')}`),
        h('div', {}, ['状态：', statusTag(row.income_status)]),
      ])
    },
  },
  {
    title: '结算时间',
    key: 'settled_at',
    width: 190,
    align: 'center',
    render(row) {
      if (row.biz_type === 'call') {
        return h('div', { class: 'meta-wrap' }, [
          h('div', {}, `付费方：${formatTime(row.payer_settled_at)}`),
          h('div', {}, `收益方：${formatTime(row.income_settled_at)}`),
        ])
      }
      return formatTime(row.sender_settled_at)
    },
  },
  {
    title: '创建时间',
    key: 'created_at',
    width: 170,
    align: 'center',
    render(row) {
      return formatTime(row.created_at)
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="手续费账单">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="api.getFeeBillList"
      :scroll-x="1490"
    >
      <template #queryBar>
        <QueryBarItem label="业务类型" :label-width="70">
          <NSelect
            v-model:value="queryItems.biz_type"
            clearable
            style="width: 150px"
            :options="bizTypeOptions"
            placeholder="全部"
          />
        </QueryBarItem>
        <QueryBarItem label="状态" :label-width="50">
          <NSelect
            v-model:value="queryItems.status"
            clearable
            style="width: 170px"
            :options="statusOptions"
            placeholder="全部"
          />
        </QueryBarItem>
        <QueryBarItem label="用户ID" :label-width="60">
          <NInput
            v-model:value="queryItems.user_id"
            clearable
            placeholder="请输入用户ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="记录ID" :label-width="60">
          <NInput
            v-model:value="queryItems.record_id"
            clearable
            placeholder="请输入记录ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="创建时间" :label-width="70">
          <NDatePicker
            v-model:value="datetimeRange"
            type="datetimerange"
            clearable
            placeholder="请选择创建时间范围"
            @update:value="handleDateRangeChange"
          />
        </QueryBarItem>
      </template>
    </CrudTable>
  </CommonPage>
</template>

<style scoped>
.meta-wrap {
  display: flex;
  flex-direction: column;
  gap: 4px;
  line-height: 1.35;
}

.sub {
  color: #8b8f99;
  font-size: 12px;
}
</style>
