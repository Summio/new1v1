<script setup>
import { computed, h, onMounted, ref } from 'vue'
import { NButton, NImage, NInput, NModal, NPopconfirm, NSelect, NSpace, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate, renderIcon } from '@/utils'

defineOptions({ name: '资料编辑审核' })

const $table = ref(null)
const queryItems = ref({ status: 'pending' })
const detailVisible = ref(false)
const detailLoading = ref(false)
const currentApply = ref(null)

const statusOptions = [
  { label: '待审核', value: 'pending' },
  { label: '审核中', value: 'reviewing' },
  { label: '已完成', value: 'completed' },
  { label: '已取消', value: 'cancelled' },
]

const statusMap = {
  pending: { type: 'warning', text: '待审核' },
  reviewing: { type: 'info', text: '审核中' },
  completed: { type: 'success', text: '已完成' },
  cancelled: { type: 'default', text: '已取消' },
}

const itemStatusMap = {
  pending: { type: 'warning', text: '待审核' },
  approved: { type: 'success', text: '已通过' },
  rejected: { type: 'error', text: '已驳回' },
}

const canOperate = computed(() => {
  const status = currentApply.value?.status || ''
  return status === 'pending' || status === 'reviewing'
})

const canComplete = computed(() => {
  if (!canOperate.value) return false
  const items = currentApply.value?.review_items || []
  return items.length > 0 && items.every((item) => item.status !== 'pending')
})

onMounted(() => {
  $table.value?.handleSearch()
})

function renderStatus(status) {
  const target = statusMap[status] || { type: 'default', text: status || '-' }
  return h(NTag, { type: target.type }, { default: () => target.text })
}

function renderDate(value) {
  return value ? formatDate(value, 'YYYY-MM-DD HH:mm:ss') : '-'
}

function itemStatus(item) {
  const target = itemStatusMap[item?.status] || { type: 'default', text: item?.status || '-' }
  return target
}

function operationText(item) {
  if (item.field === 'album_photos' && item.op === 'add') return '新增图片'
  if (item.field === 'album_photos' && item.op === 'remove') return '删除图片'
  return '替换'
}

function isImageItem(item) {
  return ['avatar', 'cover_url', 'album_photos'].includes(item?.field)
}

function displayValue(value) {
  if (value === null || value === undefined || value === '') return '-'
  return value
}

async function fetchData(params = {}) {
  const res = await api.getProfileReviewList({
    page: params.page,
    page_size: params.page_size,
    status: params.status || '',
    phone: params.phone || '',
    nickname: params.nickname || '',
    user_id: params.user_id || undefined,
  })
  return {
    data: res.rows || res.data || [],
    total: res.total || 0,
  }
}

async function loadDetail(id) {
  detailLoading.value = true
  try {
    const res = await api.getProfileReviewById({ id })
    currentApply.value = res.data || null
  } finally {
    detailLoading.value = false
  }
}

async function openDetail(row) {
  currentApply.value = row
  detailVisible.value = true
  await loadDetail(row.id)
}

async function refreshAfterAction() {
  if (currentApply.value?.id) {
    await loadDetail(currentApply.value.id)
  }
  $table.value?.handleSearch()
}

async function reviewItem(item, status) {
  try {
    await api.reviewProfileReviewItem({
      id: currentApply.value.id,
      item_id: item.item_id,
      status,
    })
    window.$message?.success(status === 'approved' ? '已通过该项' : '已驳回该项')
    await refreshAfterAction()
  } catch (error) {
    window.$message?.error(error?.message || '审核失败')
  }
}

async function approveAll() {
  try {
    await api.approveAllProfileReviewItems({ id: currentApply.value.id })
    window.$message?.success('已全部通过')
    await refreshAfterAction()
  } catch (error) {
    window.$message?.error(error?.message || '操作失败')
  }
}

async function rejectAll() {
  try {
    await api.rejectAllProfileReviewItems({ id: currentApply.value.id })
    window.$message?.success('已全部驳回')
    await refreshAfterAction()
  } catch (error) {
    window.$message?.error(error?.message || '操作失败')
  }
}

async function completeReview() {
  try {
    await api.completeProfileReview({ id: currentApply.value.id })
    window.$message?.success('审核已完成')
    detailVisible.value = false
    currentApply.value = null
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '完成审核失败')
  }
}

const columns = [
  { title: '申请ID', key: 'id', width: 90, align: 'center' },
  {
    title: '用户信息',
    key: 'user',
    minWidth: 220,
    render(row) {
      return h('div', {}, [
        h('div', {}, `ID: ${row.user_id}`),
        h('div', { class: 'sub' }, `昵称: ${row.nickname || '-'}`),
        h('div', { class: 'sub' }, `手机号: ${row.phone || '-'}`),
      ])
    },
  },
  {
    title: '申请状态',
    key: 'status',
    width: 100,
    align: 'center',
    render(row) {
      return renderStatus(row.status)
    },
  },
  {
    title: '变更项',
    key: 'review_item_count',
    width: 90,
    align: 'center',
  },
  {
    title: '提交时间',
    key: 'submitted_at',
    width: 170,
    align: 'center',
    render(row) {
      return renderDate(row.submitted_at)
    },
  },
  {
    title: '完成时间',
    key: 'completed_at',
    width: 170,
    align: 'center',
    render(row) {
      return renderDate(row.completed_at)
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 120,
    align: 'center',
    fixed: 'right',
    render(row) {
      return h(
        NButton,
        {
          size: 'small',
          type: 'primary',
          secondary: true,
          onClick: () => openDetail(row),
        },
        {
          default: () => '查看审核',
          icon: renderIcon('material-symbols:visibility-outline-rounded', { size: 16 }),
        }
      )
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="资料编辑审核">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="fetchData"
      :scroll-x="960"
    >
      <template #queryBar>
        <QueryBarItem label="用户ID" :label-width="55">
          <NInput v-model:value="queryItems.user_id" clearable placeholder="请输入用户ID" />
        </QueryBarItem>
        <QueryBarItem label="手机号" :label-width="55">
          <NInput v-model:value="queryItems.phone" clearable placeholder="请输入手机号" />
        </QueryBarItem>
        <QueryBarItem label="昵称" :label-width="45">
          <NInput v-model:value="queryItems.nickname" clearable placeholder="请输入昵称" />
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

    <NModal v-model:show="detailVisible" preset="card" title="资料编辑审核" style="width: 920px">
      <div v-if="currentApply" class="detail">
        <div class="detail-header">
          <div>
            <div class="detail-title">用户 {{ currentApply.user_id }}</div>
            <div class="sub">手机号：{{ currentApply.phone || '-' }}</div>
          </div>
          <NTag :type="statusMap[currentApply.status]?.type || 'default'">
            {{ statusMap[currentApply.status]?.text || currentApply.status }}
          </NTag>
        </div>

        <div v-if="canOperate" class="toolbar">
          <NSpace>
            <NPopconfirm @positive-click="approveAll">
              <template #trigger>
                <NButton type="success" secondary>全部通过</NButton>
              </template>
              确认将所有待审核项标记为通过？
            </NPopconfirm>
            <NPopconfirm @positive-click="rejectAll">
              <template #trigger>
                <NButton type="error" secondary>全部驳回</NButton>
              </template>
              确认将所有待审核项标记为驳回？
            </NPopconfirm>
            <NPopconfirm @positive-click="completeReview">
              <template #trigger>
                <NButton type="primary" :disabled="!canComplete">完成审核</NButton>
              </template>
              确认完成审核并写入已通过的资料项？
            </NPopconfirm>
          </NSpace>
        </div>

        <div v-if="detailLoading" class="loading">加载中...</div>
        <div v-else class="items">
          <div
            v-for="item in currentApply.review_items || []"
            :key="item.item_id"
            class="review-item"
          >
            <div class="item-head">
              <div>
                <strong>{{ item.label }}</strong>
                <span class="sub"> {{ operationText(item) }}</span>
              </div>
              <NTag :type="itemStatus(item).type">{{ itemStatus(item).text }}</NTag>
            </div>
            <div class="compare">
              <div class="compare-box">
                <div class="compare-label">提交前</div>
                <NImage
                  v-if="isImageItem(item) && item.before"
                  :src="item.before"
                  width="96"
                  height="96"
                  object-fit="cover"
                />
                <div v-else class="text-value">{{ displayValue(item.before) }}</div>
              </div>
              <div class="compare-box">
                <div class="compare-label">提交后</div>
                <NImage
                  v-if="isImageItem(item) && item.after"
                  :src="item.after"
                  width="96"
                  height="96"
                  object-fit="cover"
                />
                <div v-else class="text-value">{{ displayValue(item.after) }}</div>
              </div>
              <div v-if="canOperate && item.status === 'pending'" class="item-actions">
                <NButton
                  size="small"
                  type="success"
                  secondary
                  @click="reviewItem(item, 'approved')"
                >
                  通过
                </NButton>
                <NPopconfirm @positive-click="reviewItem(item, 'rejected')">
                  <template #trigger>
                    <NButton size="small" type="error" secondary>驳回</NButton>
                  </template>
                  确认驳回该项？
                </NPopconfirm>
              </div>
            </div>
          </div>
        </div>
      </div>
    </NModal>
  </CommonPage>
</template>

<style scoped>
.sub {
  color: #8b8f99;
  font-size: 12px;
}

.detail {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.detail-header,
.item-head,
.compare {
  display: flex;
  align-items: center;
  gap: 14px;
}

.detail-header,
.item-head {
  justify-content: space-between;
}

.detail-title {
  font-size: 16px;
  font-weight: 600;
}

.toolbar {
  padding: 10px 0;
}

.items {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.review-item {
  border: 1px solid #edf0f5;
  border-radius: 8px;
  padding: 12px;
}

.compare {
  margin-top: 10px;
  align-items: stretch;
}

.compare-box {
  flex: 1;
  min-width: 0;
  background: #f8f9fc;
  border-radius: 6px;
  padding: 10px;
}

.compare-label {
  color: #8b8f99;
  font-size: 12px;
  margin-bottom: 8px;
}

.text-value {
  color: #1f2329;
  min-height: 32px;
  white-space: pre-wrap;
  word-break: break-word;
}

.item-actions {
  display: flex;
  flex-direction: column;
  gap: 8px;
  justify-content: center;
  width: 76px;
}

.loading {
  color: #8b8f99;
  padding: 20px;
  text-align: center;
}
</style>
