<script setup>
import { h, onMounted, ref } from 'vue'
import { NDatePicker, NInput, NSelect, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate } from '@/utils'

defineOptions({ name: '代币流水' })

const $table = ref(null)
const datetimeRange = ref(null)
const queryItems = ref({
  user_id: '',
  related_user_id: '',
  asset_type: null,
  direction: 'all',
  biz_type: null,
  biz_id: '',
  start_time: null,
  end_time: null,
})

const assetTypeOptions = [
  { label: '金币', value: 'coins' },
  { label: '钻石', value: 'diamonds' },
]

const directionOptions = [
  { label: '全部', value: 'all' },
  { label: '收入', value: 'income' },
  { label: '支出', value: 'expense' },
]

const bizTypeOptions = [
  { label: '充值', value: 'recharge' },
  { label: '通话', value: 'call' },
  { label: '通话手续费', value: 'call_fee' },
  { label: '礼物', value: 'gift' },
  { label: '礼物手续费', value: 'gift_fee' },
  { label: '文字聊天', value: 'im_text' },
  { label: '提现', value: 'withdraw' },
  { label: '后台调整', value: 'token_adjust' },
]

const assetTypeMap = {
  coins: '金币',
  diamonds: '钻石',
}

const directionMap = {
  income: { text: '收入', type: 'success', prefix: '+' },
  expense: { text: '支出', type: 'error', prefix: '-' },
}

const bizTypeMap = {
  recharge: '充值',
  call: '通话',
  call_fee: '通话手续费',
  gift: '礼物',
  gift_fee: '礼物手续费',
  im_text: '文字聊天',
  withdraw: '提现',
  token_adjust: '后台调整',
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

function userText(user, fallbackId, fallbackText = '-') {
  const id = user?.id || fallbackId
  if (!id) return fallbackText
  const name = user?.nickname || user?.phone || ''
  return `ID:${id} ${name}`.trim()
}

function formatTime(value) {
  return value ? formatDate(value, 'YYYY-MM-DD HH:mm:ss') : '-'
}

function formatAmount(row) {
  const direction = directionMap[row.direction] || { prefix: '' }
  const unit = assetTypeMap[row.asset_type] || row.asset_type || ''
  return `${direction.prefix}${Number(row.amount || 0)}${unit}`
}

function getBusinessLedgerList(params = {}) {
  return api.getBusinessLedgerList({
    ...params,
    user_id: params.user_id || undefined,
    related_user_id: params.related_user_id || undefined,
    asset_type: params.asset_type || undefined,
    direction: params.direction || 'all',
    biz_type: params.biz_type || undefined,
    biz_id: params.biz_id || undefined,
    start_time: params.start_time || undefined,
    end_time: params.end_time || undefined,
  })
}

const columns = [
  { title: '流水ID', key: 'id', width: 160, align: 'center' },
  {
    title: '用户',
    key: 'user',
    minWidth: 180,
    render(row) {
      return userText(row.user, row.user_id)
    },
  },
  {
    title: '方向',
    key: 'direction',
    width: 90,
    align: 'center',
    render(row) {
      const target = directionMap[row.direction] || { text: row.direction || '-', type: 'default' }
      return h(NTag, { type: target.type, bordered: false }, { default: () => target.text })
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
    title: '业务',
    key: 'biz_type',
    width: 110,
    align: 'center',
    render(row) {
      return bizTypeMap[row.biz_type] || row.biz_type || '-'
    },
  },
  { title: '业务ID', key: 'biz_id', width: 90, align: 'center' },
  {
    title: '关联方',
    key: 'related_user',
    minWidth: 180,
    render(row) {
      return userText(row.related_user, row.related_user_id, row.related_user?.nickname || '平台')
    },
  },
  {
    title: '说明',
    key: 'title',
    minWidth: 220,
    render(row) {
      const remark = row.remark ? ` / ${row.remark}` : ''
      return `${row.title || '-'}${remark}`
    },
  },
  { title: '金额', key: 'amount', width: 140, align: 'right', render: formatAmount },
  {
    title: '状态/备注',
    key: 'status',
    minWidth: 170,
    render(row) {
      const status = row.status || '-'
      if (row.operator_user_id || row.operator_username) {
        return h('div', { class: 'meta-wrap' }, [
          h('div', {}, status),
          h(
            'div',
            { class: 'sub' },
            `操作人：ID:${row.operator_user_id || '-'} ${row.operator_username || ''}`
          ),
        ])
      }
      return status
    },
  },
  {
    title: '时间',
    key: 'created_at',
    width: 170,
    align: 'center',
    render(row) {
      return formatTime(row.created_at || row.event_time)
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="代币流水">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="getBusinessLedgerList"
      :scroll-x="1580"
    >
      <template #queryBar>
        <QueryBarItem label="用户ID" :label-width="60">
          <NInput
            v-model:value="queryItems.user_id"
            clearable
            placeholder="请输入用户ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="关联用户ID" :label-width="80">
          <NInput
            v-model:value="queryItems.related_user_id"
            clearable
            placeholder="请输入关联用户ID"
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
            v-model:value="queryItems.direction"
            clearable
            style="width: 130px"
            :options="directionOptions"
            placeholder="全部"
          />
        </QueryBarItem>
        <QueryBarItem label="业务类型" :label-width="70">
          <NSelect
            v-model:value="queryItems.biz_type"
            clearable
            style="width: 150px"
            :options="bizTypeOptions"
            placeholder="全部"
          />
        </QueryBarItem>
        <QueryBarItem label="业务ID" :label-width="60">
          <NInput
            v-model:value="queryItems.biz_id"
            clearable
            placeholder="请输入业务ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="时间" :label-width="50">
          <NDatePicker
            v-model:value="datetimeRange"
            type="datetimerange"
            clearable
            placeholder="请选择时间范围"
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
