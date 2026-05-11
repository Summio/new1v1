<script setup>
import { h, onMounted, ref } from 'vue'
import { NButton, NInput, NModal, NPopconfirm, NSpace } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate, renderIcon } from '@/utils'

defineOptions({ name: '意见反馈管理' })

const $table = ref(null)
const queryItems = ref({
  user_id: '',
  keyword: '',
})
const detailVisible = ref(false)
const currentFeedback = ref(null)

onMounted(() => {
  $table.value?.handleSearch()
})

function renderDate(value) {
  return value ? formatDate(value, 'YYYY-MM-DD HH:mm:ss') : '-'
}

function openDetail(row) {
  currentFeedback.value = row
  detailVisible.value = true
}

async function fetchData(params = {}) {
  const res = await api.getFeedbackList({
    page: params.page,
    page_size: params.page_size,
    user_id: params.user_id || undefined,
    keyword: params.keyword || '',
  })
  return {
    data: res.data || [],
    total: res.total || 0,
  }
}

async function handleDelete(row) {
  try {
    await api.deleteFeedback({ id: row.id })
    window.$message?.success('删除成功')
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '删除失败')
  }
}

const columns = [
  { title: '反馈ID', key: 'id', width: 90, align: 'center' },
  {
    title: '用户',
    key: 'user',
    width: 220,
    render(row) {
      return h('div', {}, [
        h('div', {}, `ID: ${row.user_id}`),
        h('div', { class: 'sub' }, `${row.nickname || '-'} / ${row.phone || '-'}`),
      ])
    },
  },
  {
    title: '反馈内容',
    key: 'content',
    minWidth: 320,
    ellipsis: { tooltip: true },
    render(row) {
      return row.content || '-'
    },
  },
  {
    title: '提交时间',
    key: 'created_at',
    width: 180,
    align: 'center',
    render(row) {
      return renderDate(row.created_at)
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 160,
    align: 'center',
    fixed: 'right',
    render(row) {
      return h(NSpace, { justify: 'center', size: 8 }, () => [
        h(
          NButton,
          {
            size: 'small',
            secondary: true,
            onClick: () => openDetail(row),
          },
          {
            default: () => '查看',
            icon: renderIcon('material-symbols:visibility-outline', { size: 16 }),
          }
        ),
        h(
          NPopconfirm,
          {
            onPositiveClick: () => handleDelete(row),
          },
          {
            trigger: () =>
              h(
                NButton,
                {
                  size: 'small',
                  type: 'error',
                  secondary: true,
                },
                {
                  default: () => '删除',
                  icon: renderIcon('material-symbols:delete-outline', { size: 16 }),
                }
              ),
            default: () => '确认删除这条反馈？',
          }
        ),
      ])
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="意见反馈管理">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="fetchData"
      :scroll-x="1100"
    >
      <template #queryBar>
        <QueryBarItem label="用户ID" :label-width="55">
          <NInput v-model:value="queryItems.user_id" clearable placeholder="请输入用户ID" />
        </QueryBarItem>
        <QueryBarItem label="关键词" :label-width="55">
          <NInput v-model:value="queryItems.keyword" clearable placeholder="请输入反馈内容关键词" />
        </QueryBarItem>
      </template>
    </CrudTable>

    <NModal v-model:show="detailVisible" preset="card" title="意见反馈详情" style="width: 760px">
      <div v-if="currentFeedback" class="detail">
        <div class="detail-header">
          <div class="detail-title">反馈 {{ currentFeedback.id }}</div>
          <div class="sub">{{ renderDate(currentFeedback.created_at) }}</div>
        </div>
        <div class="detail-meta">
          <div class="detail-meta-item">用户ID：{{ currentFeedback.user_id }}</div>
          <div class="detail-meta-item">昵称：{{ currentFeedback.nickname || '-' }}</div>
          <div class="detail-meta-item">手机号：{{ currentFeedback.phone || '-' }}</div>
        </div>
        <div class="detail-block">
          <div class="detail-label">反馈内容</div>
          <div class="detail-content">{{ currentFeedback.content || '-' }}</div>
        </div>
      </div>
    </NModal>
  </CommonPage>
</template>

<style scoped>
.sub {
  color: #8b8f99;
  font-size: 12px;
  margin-top: 2px;
}

.detail {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.detail-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.detail-title {
  font-size: 18px;
  font-weight: 600;
  color: #1f2329;
}

.detail-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 16px;
  color: #4e5969;
  font-size: 13px;
}

.detail-meta-item {
  min-width: 0;
}

.detail-block {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.detail-label {
  font-size: 13px;
  font-weight: 600;
  color: #1f2329;
}

.detail-content {
  white-space: pre-wrap;
  line-height: 1.6;
  color: #1f2329;
  background: #f7f8fb;
  border-radius: 8px;
  padding: 12px;
}
</style>
