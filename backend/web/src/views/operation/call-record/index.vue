<script setup>
import { h, onMounted, ref } from 'vue'
import { NInput, NSelect, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate } from '@/utils'

defineOptions({ name: '通话记录' })

const $table = ref(null)
const queryItems = ref({})

onMounted(() => {
  $table.value?.handleSearch()
})

const statusOptions = [
  { label: '待接听', value: 'pending' },
  { label: '通话中', value: 'ongoing' },
  { label: '已结束', value: 'ended' },
  { label: '失败', value: 'failed' },
  { label: '超时', value: 'timeout' },
]

const endReasonMap = {
  normal: '正常结束',
  rejected: '被叫拒接',
  cancelled: '主叫取消',
  timeout: '呼叫超时',
  balance_empty: '余额不足',
  force_exit: '用户离场',
}

const endReasonOptions = [
  { label: '正常结束', value: 'normal' },
  { label: '被叫拒接', value: 'rejected' },
  { label: '主叫取消', value: 'cancelled' },
  { label: '呼叫超时', value: 'timeout' },
  { label: '余额不足', value: 'balance_empty' },
  { label: '用户离场', value: 'force_exit' },
]

function toCoins(value) {
  return Number(value || 0)
}

function formatDuration(seconds) {
  const total = Number(seconds || 0)
  const hVal = Math.floor(total / 3600)
  const mVal = Math.floor((total % 3600) / 60)
  const sVal = total % 60
  if (hVal > 0) return `${hVal}小时 ${mVal}分 ${sVal}秒`
  if (mVal > 0) return `${mVal}分 ${sVal}秒`
  return `${sVal}秒`
}

const columns = [
  { title: '通话ID', key: 'id', width: 90, align: 'center' },
  {
    title: '主叫',
    key: 'caller',
    width: 220,
    render(row) {
      return h('div', {}, [
        h('div', {}, `ID: ${row.caller_id}`),
        h('div', { class: 'sub' }, `${row.caller_nickname || '-'} / ${row.caller_phone || '-'}`),
      ])
    },
  },
  {
    title: '被叫',
    key: 'callee',
    width: 220,
    render(row) {
      return h('div', {}, [
        h('div', {}, `ID: ${row.callee_id}`),
        h('div', { class: 'sub' }, `${row.callee_nickname || '-'} / ${row.callee_phone || '-'}`),
      ])
    },
  },
  { title: '单价(分/分钟)', key: 'call_price', width: 120, align: 'center' },
  {
    title: '时长',
    key: 'duration',
    width: 100,
    align: 'center',
    render(row) {
      return formatDuration(row.duration)
    },
  },
  {
    title: '总费用(金币)',
    key: 'total_fee',
    width: 100,
    align: 'center',
    render(row) {
      return toCoins(row.total_fee)
    },
  },
  {
    title: '收益认证用户',
    key: 'income_anchor_user_id',
    width: 100,
    align: 'center',
    render(row) {
      return row.income_anchor_user_id || '-'
    },
  },
  {
    title: '认证用户收益(钻石)',
    key: 'anchor_income_diamonds',
    width: 130,
    align: 'center',
    render(row) {
      return toCoins(row.anchor_income_diamonds)
    },
  },
  {
    title: '分成比例',
    key: 'anchor_share_bps',
    width: 100,
    align: 'center',
    render(row) {
      const bps = Number(row.anchor_share_bps || 0)
      if (!Number.isFinite(bps) || bps <= 0) return '-'
      return `${(bps / 100).toFixed(2)}%`
    },
  },
  {
    title: '收益结算时间',
    key: 'income_settled_at',
    width: 160,
    align: 'center',
    render(row) {
      return row.income_settled_at ? formatDate(row.income_settled_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '状态',
    key: 'status',
    width: 90,
    align: 'center',
    render(row) {
      const map = {
        pending: { type: 'warning', text: '待接听' },
        ongoing: { type: 'info', text: '通话中' },
        ended: { type: 'success', text: '已结束' },
        failed: { type: 'error', text: '失败' },
        timeout: { type: 'default', text: '超时' },
      }
      const target = map[row.status] || { type: 'default', text: row.status || '-' }
      return h(NTag, { type: target.type }, { default: () => target.text })
    },
  },
  {
    title: '结束原因',
    key: 'end_reason',
    width: 120,
    align: 'center',
    render(row) {
      if (!row.end_reason) return '-'
      return endReasonMap[row.end_reason] || row.end_reason
    },
  },
  {
    title: '接通时间',
    key: 'connected_at',
    width: 160,
    align: 'center',
    render(row) {
      return row.connected_at ? formatDate(row.connected_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '结束时间',
    key: 'ended_at',
    width: 160,
    align: 'center',
    render(row) {
      return row.ended_at ? formatDate(row.ended_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '创建时间',
    key: 'created_at',
    width: 160,
    align: 'center',
    render(row) {
      return row.created_at ? formatDate(row.created_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="通话记录">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="api.getCallRecordList"
      :scroll-x="2010"
    >
      <template #queryBar>
        <QueryBarItem label="通话ID" :label-width="60">
          <NInput
            v-model:value="queryItems.call_id"
            clearable
            type="text"
            placeholder="请输入通话ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="主叫ID" :label-width="60">
          <NInput
            v-model:value="queryItems.caller_id"
            clearable
            type="text"
            placeholder="请输入主叫ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="被叫ID" :label-width="60">
          <NInput
            v-model:value="queryItems.callee_id"
            clearable
            type="text"
            placeholder="请输入被叫ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="状态" :label-width="50">
          <NSelect
            v-model:value="queryItems.status"
            clearable
            style="width: 160px"
            :options="statusOptions"
            placeholder="请选择状态"
          />
        </QueryBarItem>
        <QueryBarItem label="结束原因" :label-width="70">
          <NSelect
            v-model:value="queryItems.end_reason"
            clearable
            style="width: 180px"
            :options="endReasonOptions"
            placeholder="请选择结束原因"
          />
        </QueryBarItem>
      </template>
    </CrudTable>
  </CommonPage>
</template>

<style scoped>
.sub {
  color: #8b8f99;
  font-size: 12px;
  margin-top: 2px;
}
</style>
