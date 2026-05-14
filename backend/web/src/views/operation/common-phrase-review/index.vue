<script setup>
import { h, onMounted, ref } from 'vue'
import { NButton, NInput, NSelect, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate } from '@/utils'

defineOptions({ name: '常用语审核' })

const $table = ref(null)
const queryItems = ref({
  status: 'pending',
})

const statusOptions = [
  { label: '全部', value: 'all' },
  { label: '待审核', value: 'pending' },
  { label: '已通过', value: 'approved' },
  { label: '已驳回', value: 'rejected' },
]

const statusMap = {
  pending: { type: 'warning', text: '待审核' },
  approved: { type: 'success', text: '已通过' },
  rejected: { type: 'error', text: '已驳回' },
  none: { type: 'default', text: '未设置' },
}

onMounted(() => {
  $table.value?.handleSearch()
})

async function getCommonPhraseReviewList(params = {}) {
  const res = await api.getCommonPhraseReviewList(params)
  return {
    data: res.rows || res.data || [],
    total: res.total || 0,
  }
}

async function handleReview(row, status) {
  if (!row?.id) return
  if (status === 'approved') {
    const ok = window.confirm('确认审核通过该常用语？')
    if (!ok) return
    await api.reviewCommonPhrase({ id: row.id, status: 'approved', review_remark: '' })
    window.$message?.success('审核通过')
    $table.value?.handleSearch()
    return
  }
  const reason = window.prompt('请输入驳回原因（必填）', row.review_remark || '')
  if (reason === null) return
  const reviewRemark = reason.trim()
  if (!reviewRemark) {
    window.$message?.warning('驳回原因不能为空')
    return
  }
  await api.reviewCommonPhrase({ id: row.id, status: 'rejected', review_remark: reviewRemark })
  window.$message?.success('审核驳回')
  $table.value?.handleSearch()
}

function renderStatus(row) {
  const target = statusMap[row.review_status] || {
    type: 'default',
    text: row.review_status || '-',
  }
  return h(NTag, { type: target.type }, { default: () => target.text })
}

const columns = [
  { title: '用户ID', key: 'user_id', width: 90, align: 'center' },
  {
    title: '账号信息',
    key: 'account',
    width: 220,
    render(row) {
      return h('div', {}, [
        h('div', {}, `昵称: ${row.nickname || '-'}`),
        h('div', { class: 'sub' }, `手机号: ${row.phone || '-'}`),
      ])
    },
  },
  { title: '槽位', key: 'slot_index', width: 70, align: 'center' },
  {
    title: '审核状态',
    key: 'review_status',
    width: 100,
    align: 'center',
    render: renderStatus,
  },
  {
    title: '已通过内容',
    key: 'approved_content',
    minWidth: 180,
    render(row) {
      return row.approved_content || '-'
    },
  },
  {
    title: '待审核内容',
    key: 'pending_content',
    minWidth: 180,
    render(row) {
      return row.pending_content || '-'
    },
  },
  {
    title: '驳回原因',
    key: 'review_remark',
    minWidth: 160,
    render(row) {
      return row.review_remark || '-'
    },
  },
  {
    title: '提交时间',
    key: 'submitted_at',
    width: 160,
    align: 'center',
    render(row) {
      return row.submitted_at ? formatDate(row.submitted_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '审核时间',
    key: 'reviewed_at',
    width: 160,
    align: 'center',
    render(row) {
      return row.reviewed_at ? formatDate(row.reviewed_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 180,
    align: 'center',
    fixed: 'right',
    render(row) {
      if (row.review_status !== 'pending') return '-'
      return h('div', { style: 'display:flex;gap:8px;justify-content:center;' }, [
        h(
          NButton,
          {
            size: 'tiny',
            type: 'success',
            secondary: true,
            onClick: async () => {
              try {
                await handleReview(row, 'approved')
              } catch (error) {
                window.$message?.error(error?.message || '审核失败')
              }
            },
          },
          { default: () => '审核通过' }
        ),
        h(
          NButton,
          {
            size: 'tiny',
            type: 'error',
            secondary: true,
            onClick: async () => {
              try {
                await handleReview(row, 'rejected')
              } catch (error) {
                window.$message?.error(error?.message || '审核失败')
              }
            },
          },
          { default: () => '审核驳回' }
        ),
      ])
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="常用语审核">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="getCommonPhraseReviewList"
      :scroll-x="1450"
    >
      <template #queryBar>
        <QueryBarItem label="用户ID" :label-width="60">
          <NInput
            v-model:value="queryItems.user_id"
            clearable
            type="text"
            placeholder="请输入用户ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="手机号" :label-width="60">
          <NInput
            v-model:value="queryItems.phone"
            clearable
            type="text"
            placeholder="请输入手机号"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="昵称" :label-width="50">
          <NInput
            v-model:value="queryItems.nickname"
            clearable
            type="text"
            placeholder="请输入昵称"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="审核状态" :label-width="70">
          <NSelect
            v-model:value="queryItems.status"
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
</style>
