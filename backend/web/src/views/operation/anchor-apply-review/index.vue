<script setup>
import { h, onMounted, ref } from 'vue'
import { NButton, NImage, NInput, NSelect, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate } from '@/utils'

defineOptions({ name: '主播申请审核' })

const $table = ref(null)
const queryItems = ref({
  anchor_apply_status: 'pending',
})

const statusOptions = [
  { label: '待审核', value: 'pending' },
  { label: '已通过', value: 'approved' },
  { label: '已驳回', value: 'rejected' },
]

const statusMap = {
  pending: { type: 'warning', text: '待审核' },
  approved: { type: 'success', text: '已通过' },
  rejected: { type: 'error', text: '已驳回' },
}

onMounted(() => {
  $table.value?.handleSearch()
})

async function getAnchorApplyReviewList(params = {}) {
  const query = { ...params }
  if (!query.anchor_apply_status) {
    query.anchor_apply_status = 'pending'
  }
  const res = await api.getAppUserList(query)
  const rows = Array.isArray(res?.data) ? res.data : []
  const filtered = rows.filter((item) => (item?.anchor_apply_status || 'none') !== 'none')
  return {
    ...res,
    data: filtered,
  }
}

async function handleQuickReview(row, status) {
  if (!row?.id) return
  if (status === 'approved') {
    const ok = window.confirm('确认通过该主播申请？')
    if (!ok) return
    await api.reviewAnchorApply({ id: row.id, status: 'approved' })
    window.$message?.success('审核通过')
    $table.value?.handleSearch()
    return
  }
  const reason = window.prompt('请输入驳回原因（必填）', row.anchor_reject_reason || '')
  if (reason === null) return
  const trimmed = reason.trim()
  if (!trimmed) {
    window.$message?.warning('驳回原因不能为空')
    return
  }
  await api.reviewAnchorApply({
    id: row.id,
    status: 'rejected',
    reject_reason: trimmed,
  })
  window.$message?.success('已驳回申请')
  $table.value?.handleSearch()
}

const columns = [
  { title: '用户ID', key: 'id', width: 90, align: 'center' },
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
  {
    title: '申请状态',
    key: 'anchor_apply_status',
    width: 100,
    align: 'center',
    render(row) {
      const target = statusMap[row.anchor_apply_status] || {
        type: 'default',
        text: row.anchor_apply_status || '-',
      }
      return h(NTag, { type: target.type }, { default: () => target.text })
    },
  },
  {
    title: '申请时间',
    key: 'anchor_apply_at',
    width: 160,
    align: 'center',
    render(row) {
      return row.anchor_apply_at ? formatDate(row.anchor_apply_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '正面照',
    key: 'anchor_apply_face_image',
    width: 120,
    align: 'center',
    render(row) {
      if (!row.anchor_apply_face_image) return '-'
      return h(NImage, {
        src: row.anchor_apply_face_image,
        width: 64,
        height: 84,
        objectFit: 'cover',
        previewDisabled: false,
      })
    },
  },
  {
    title: '驳回原因',
    key: 'anchor_reject_reason',
    minWidth: 220,
    render(row) {
      return row.anchor_reject_reason || '-'
    },
  },
  {
    title: '审核时间',
    key: 'anchor_reviewed_at',
    width: 160,
    align: 'center',
    render(row) {
      return row.anchor_reviewed_at ? formatDate(row.anchor_reviewed_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 180,
    align: 'center',
    fixed: 'right',
    render(row) {
      if (row.anchor_apply_status !== 'pending') return '-'
      return h('div', { style: 'display:flex;gap:8px;justify-content:center;' }, [
        h(
          NButton,
          {
            size: 'tiny',
            type: 'success',
            secondary: true,
            onClick: async () => {
              try {
                await handleQuickReview(row, 'approved')
              } catch (error) {
                window.$message?.error(error?.message || '审核失败')
              }
            },
          },
          { default: () => '通过' }
        ),
        h(
          NButton,
          {
            size: 'tiny',
            type: 'error',
            secondary: true,
            onClick: async () => {
              try {
                await handleQuickReview(row, 'rejected')
              } catch (error) {
                window.$message?.error(error?.message || '审核失败')
              }
            },
          },
          { default: () => '驳回' }
        ),
      ])
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="主播申请审核">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="getAnchorApplyReviewList"
      :scroll-x="1250"
    >
      <template #queryBar>
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
        <QueryBarItem label="申请状态" :label-width="70">
          <NSelect
            v-model:value="queryItems.anchor_apply_status"
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
