<script setup>
import { h, onMounted, ref } from 'vue'
import { NButton, NImage, NInput, NPopconfirm, NSelect, NSpace, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate, renderIcon } from '@/utils'

defineOptions({ name: '提现管理' })

const $table = ref(null)
const queryItems = ref({})

onMounted(() => {
  $table.value?.handleSearch()
})

const statusOptions = [
  { label: '待处理', value: 'pending' },
  { label: '已打款', value: 'paid' },
  { label: '已驳回', value: 'rejected' },
]

function renderStatus(status) {
  const statusMap = {
    pending: { type: 'warning', text: '待处理' },
    paid: { type: 'success', text: '已打款' },
    approved: { type: 'success', text: '已打款' },
    rejected: { type: 'error', text: '已驳回' },
  }
  const target = statusMap[status] || { type: 'default', text: status || '-' }
  return h(NTag, { type: target.type }, { default: () => target.text })
}

function renderDate(value) {
  return value ? formatDate(value, 'YYYY-MM-DD HH:mm:ss') : '-'
}

async function fetchData(params = {}) {
  const res = await api.getWithdrawList({
    page: params.page,
    page_size: params.page_size,
    status: params.status || '',
    user_id: params.user_id || undefined,
    real_name: params.real_name || '',
    account_no: params.account_no || '',
  })
  return {
    data: res.data || [],
    total: res.total || 0,
  }
}

async function handleReview(row, action, remark = '') {
  try {
    await api.reviewWithdrawApply({
      withdraw_id: row.id,
      action,
      review_remark: remark,
    })
    window.$message?.success(action === 'approve' ? '已确认打款' : '已驳回')
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '操作失败')
  }
}

function rejectWithdraw(row) {
  window.$dialog?.warning({
    title: '驳回提现',
    content: () =>
      h(NInput, {
        type: 'textarea',
        placeholder: '请输入驳回原因',
        autosize: { minRows: 3, maxRows: 5 },
        onUpdateValue: (value) => {
          row._rejectRemark = value
        },
      }),
    positiveText: '确认驳回',
    negativeText: '取消',
    onPositiveClick: () => {
      const remark = (row._rejectRemark || '').trim()
      if (!remark) {
        window.$message?.warning('请填写驳回原因')
        return false
      }
      return handleReview(row, 'reject', remark)
    },
  })
}

const columns = [
  { title: '申请ID', key: 'id', width: 90, align: 'center' },
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
    title: '提现钻石',
    key: 'amount',
    width: 110,
    align: 'center',
  },
  {
    title: '支付宝资料',
    key: 'account',
    minWidth: 240,
    render(row) {
      return h('div', {}, [
        h('div', {}, row.real_name || '-'),
        h('div', { class: 'sub' }, row.account_no || row.account_no_masked || '-'),
      ])
    },
  },
  {
    title: '收款码',
    key: 'payment_qr_code',
    width: 120,
    align: 'center',
    render(row) {
      if (!row.payment_qr_code) return '-'
      return h('div', { class: 'qr-cell' }, [
        h(NImage, {
          width: 56,
          height: 56,
          src: row.payment_qr_code,
          objectFit: 'cover',
        }),
      ])
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
    title: '申请时间',
    key: 'created_at',
    width: 170,
    align: 'center',
    render(row) {
      return renderDate(row.created_at)
    },
  },
  {
    title: '处理时间',
    key: 'processed_at',
    width: 170,
    align: 'center',
    render(row) {
      return renderDate(row.processed_at)
    },
  },
  {
    title: '处理备注',
    key: 'review_remark',
    minWidth: 160,
    ellipsis: { tooltip: true },
    render(row) {
      return row.review_remark || '-'
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 210,
    align: 'center',
    fixed: 'right',
    render(row) {
      if (row.status !== 'pending') return '-'
      return h(NSpace, { justify: 'center', size: 8 }, () => [
        h(
          NPopconfirm,
          {
            onPositiveClick: () => handleReview(row, 'approve', '已确认支付宝打款'),
          },
          {
            trigger: () =>
              h(
                NButton,
                { size: 'small', type: 'primary' },
                {
                  default: () => '确认已打款',
                  icon: renderIcon('material-symbols:check-circle-outline', { size: 16 }),
                }
              ),
            default: () => '确认已向该支付宝账户打款？',
          }
        ),
        h(
          NButton,
          {
            size: 'small',
            type: 'error',
            secondary: true,
            onClick: () => rejectWithdraw(row),
          },
          {
            default: () => '驳回',
            icon: renderIcon('material-symbols:cancel-outline-rounded', { size: 16 }),
          }
        ),
      ])
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="提现管理">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="fetchData"
      :scroll-x="1530"
    >
      <template #queryBar>
        <QueryBarItem label="用户ID" :label-width="55">
          <NInput v-model:value="queryItems.user_id" clearable placeholder="请输入用户ID" />
        </QueryBarItem>
        <QueryBarItem label="姓名" :label-width="45">
          <NInput v-model:value="queryItems.real_name" clearable placeholder="请输入真实姓名" />
        </QueryBarItem>
        <QueryBarItem label="支付宝" :label-width="55">
          <NInput v-model:value="queryItems.account_no" clearable placeholder="请输入支付宝账号" />
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

.qr-cell {
  display: flex;
  justify-content: center;
}
</style>
