<script setup>
import { h, onMounted, ref } from 'vue'
import { NDatePicker, NInput, NSelect, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate } from '@/utils'

defineOptions({ name: '代币修改记录' })

const $table = ref(null)
const datetimeRange = ref(null)
const queryItems = ref({
  app_user_id: '',
  operator_user_id: '',
  asset_type: null,
  action: null,
  start_time: null,
  end_time: null,
})

const assetTypeOptions = [
  { label: '金币', value: 'coins' },
  { label: '钻石', value: 'diamonds' },
]

const actionOptions = [
  { label: '增加', value: 'increase' },
  { label: '扣除', value: 'decrease' },
]

const assetTypeMap = {
  coins: '金币',
  diamonds: '钻石',
}

const actionMap = {
  increase: { text: '增加', type: 'success', prefix: '+' },
  decrease: { text: '扣除', type: 'error', prefix: '-' },
}

onMounted(() => {
  $table.value?.handleSearch()
})

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

function userText(user, fallbackId) {
  const id = user?.id || fallbackId
  if (!id) return '-'
  const name = user?.nickname || user?.phone || ''
  return `ID:${id} ${name}`.trim()
}

function formatAmount(row) {
  const action = actionMap[row.action] || { prefix: '' }
  const unit = assetTypeMap[row.asset_type] || row.asset_type || ''
  return `${action.prefix}${Number(row.amount || 0)}${unit}`
}

function formatBalance(value, assetType) {
  const unit = assetTypeMap[assetType] || assetType || ''
  return `${Number(value || 0)}${unit}`
}

function formatTime(value) {
  return value ? formatDate(value, 'YYYY-MM-DD HH:mm:ss') : '-'
}

function getTokenAdjustRecordList(params = {}) {
  return api.getTokenAdjustRecordList({
    ...params,
    app_user_id: params.app_user_id || undefined,
    operator_user_id: params.operator_user_id || undefined,
    asset_type: params.asset_type || undefined,
    action: params.action || undefined,
    start_time: params.start_time || undefined,
    end_time: params.end_time || undefined,
  })
}

const columns = [
  { title: '记录ID', key: 'id', width: 90, align: 'center' },
  {
    title: '用户',
    key: 'app_user',
    minWidth: 180,
    render(row) {
      return userText(row.app_user, row.app_user_id)
    },
  },
  {
    title: '操作人',
    key: 'operator_user_id',
    minWidth: 160,
    render(row) {
      const username = row.operator_username || ''
      return `ID:${row.operator_user_id || '-'} ${username}`.trim()
    },
  },
  {
    title: '资产',
    key: 'asset_type',
    width: 90,
    align: 'center',
    render(row) {
      return assetTypeMap[row.asset_type] || row.asset_type || '-'
    },
  },
  {
    title: '方向',
    key: 'action',
    width: 90,
    align: 'center',
    render(row) {
      const target = actionMap[row.action] || { text: row.action || '-', type: 'default' }
      return h(NTag, { type: target.type, bordered: false }, { default: () => target.text })
    },
  },
  { title: '数量', key: 'amount', width: 120, align: 'right', render: formatAmount },
  {
    title: '调整前',
    key: 'before_amount',
    width: 120,
    align: 'right',
    render(row) {
      return formatBalance(row.before_amount, row.asset_type)
    },
  },
  {
    title: '调整后',
    key: 'after_amount',
    width: 120,
    align: 'right',
    render(row) {
      return formatBalance(row.after_amount, row.asset_type)
    },
  },
  { title: '原因', key: 'reason', minWidth: 260 },
  {
    title: '时间',
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
  <CommonPage show-footer title="代币修改记录">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="getTokenAdjustRecordList"
      :scroll-x="1400"
    >
      <template #queryBar>
        <QueryBarItem label="用户ID" :label-width="60">
          <NInput
            v-model:value="queryItems.app_user_id"
            clearable
            placeholder="请输入用户ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="操作人ID" :label-width="70">
          <NInput
            v-model:value="queryItems.operator_user_id"
            clearable
            placeholder="请输入操作人ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="资产" :label-width="50">
          <NSelect
            v-model:value="queryItems.asset_type"
            clearable
            style="width: 130px"
            :options="assetTypeOptions"
            placeholder="全部"
          />
        </QueryBarItem>
        <QueryBarItem label="方向" :label-width="50">
          <NSelect
            v-model:value="queryItems.action"
            clearable
            style="width: 130px"
            :options="actionOptions"
            placeholder="全部"
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
