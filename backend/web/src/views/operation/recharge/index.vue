<script setup>
import { h, onMounted, ref } from 'vue'
import { NButton, NInput, NPopconfirm, NSelect, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate, renderIcon } from '@/utils'

defineOptions({ name: '充值管理' })

const $table = ref(null)
const queryItems = ref({})

onMounted(() => {
  $table.value?.handleSearch()
})

const statusOptions = [
  { label: '待支付', value: 'pending' },
  { label: '已支付', value: 'paid' },
  { label: '已退款', value: 'refunded' },
]

const channelOptions = [
  { label: '微信', value: 'wx' },
  { label: '支付宝', value: 'alipay' },
]

function renderStatus(status) {
  const statusMap = {
    pending: { type: 'warning', text: '待支付' },
    paid: { type: 'success', text: '已支付' },
    refunded: { type: 'error', text: '已退款' },
  }
  const target = statusMap[status] || { type: 'default', text: status || '-' }
  return h(NTag, { type: target.type }, { default: () => target.text })
}

function renderChannel(channel) {
  if (!channel) return '-'
  if (channel === 'wx') return '微信'
  if (channel === 'alipay') return '支付宝'
  return channel
}

async function fetchData(params = {}) {
  const res = await api.getRechargeList({
    page: params.page,
    page_size: params.page_size,
    status: params.status || '',
    user_id: params.user_id || undefined,
    order_no: params.order_no || '',
    pay_channel: params.pay_channel || '',
  })
  return {
    data: res.data || [],
    total: res.total || 0,
  }
}

async function handleReview(row, action) {
  try {
    await api.reviewRechargeOrder({
      order_id: row.id,
      action,
    })
    window.$message?.success('已标记支付成功')
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '操作失败')
  }
}

const columns = [
  { title: '订单ID', key: 'id', width: 90, align: 'center' },
  {
    title: '订单号',
    key: 'order_no',
    minWidth: 220,
  },
  {
    title: '用户',
    key: 'user',
    width: 180,
    render(row) {
      return h('div', {}, [
        h('div', {}, `ID: ${row.user_id}`),
        h('div', { class: 'sub' }, row.username || '-'),
      ])
    },
  },
  {
    title: '充值金额(金币)',
    key: 'amount',
    width: 120,
    align: 'center',
    render(row) {
      return Number(row.amount || 0).toFixed(2)
    },
  },
  {
    title: '支付渠道',
    key: 'pay_channel',
    width: 100,
    align: 'center',
    render(row) {
      return renderChannel(row.pay_channel)
    },
  },
  {
    title: '状态',
    key: 'status',
    width: 90,
    align: 'center',
    render(row) {
      return renderStatus(row.status)
    },
  },
  {
    title: '支付时间',
    key: 'paid_at',
    width: 170,
    align: 'center',
    render(row) {
      return row.paid_at ? formatDate(row.paid_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '创建时间',
    key: 'created_at',
    width: 170,
    align: 'center',
    render(row) {
      return row.created_at ? formatDate(row.created_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 140,
    align: 'center',
    render(row) {
      if (row.status !== 'pending') return '-'
      return [
        h(
          NPopconfirm,
          {
            onPositiveClick: () => handleReview(row, 'mark_paid'),
          },
          {
            trigger: () =>
              h(
                NButton,
                {
                  size: 'small',
                  type: 'primary',
                  style: 'margin-right: 8px;',
                },
                {
                  default: () => '标记支付',
                  icon: renderIcon('material-symbols:check-circle-outline', { size: 16 }),
                }
              ),
            default: () => '确认标记该订单为已支付？',
          }
        ),
      ]
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="充值管理">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="fetchData"
      :scroll-x="1360"
    >
      <template #queryBar>
        <QueryBarItem label="订单号" :label-width="55">
          <NInput v-model:value="queryItems.order_no" clearable placeholder="请输入订单号" />
        </QueryBarItem>
        <QueryBarItem label="用户ID" :label-width="55">
          <NInput v-model:value="queryItems.user_id" clearable placeholder="请输入用户ID" />
        </QueryBarItem>
        <QueryBarItem label="状态" :label-width="45">
          <NSelect
            v-model:value="queryItems.status"
            clearable
            style="width: 160px"
            :options="statusOptions"
            placeholder="请选择状态"
          />
        </QueryBarItem>
        <QueryBarItem label="渠道" :label-width="45">
          <NSelect
            v-model:value="queryItems.pay_channel"
            clearable
            style="width: 160px"
            :options="channelOptions"
            placeholder="请选择渠道"
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
