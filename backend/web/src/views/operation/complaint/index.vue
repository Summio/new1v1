<script setup>
import { h, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  NButton,
  NDatePicker,
  NForm,
  NFormItem,
  NInput,
  NModal,
  NSelect,
  NSpace,
  NTag,
} from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate, renderIcon } from '@/utils'

defineOptions({ name: '投诉管理' })

const router = useRouter()
const $table = ref(null)
const detailVisible = ref(false)
const handleVisible = ref(false)
const currentComplaint = ref(null)
const handleLoading = ref(false)
const queryItems = ref({
  complainant_id: '',
  target_user_id: '',
  status: null,
  scene: null,
  keyword: '',
  start_time: null,
  end_time: null,
})
const datetimeRange = ref(null)
const handleForm = reactive({
  id: null,
  status: 'processing',
  handle_remark: '',
})

const statusOptions = [
  { label: '待处理', value: 'pending' },
  { label: '处理中', value: 'processing' },
  { label: '已处理', value: 'resolved' },
  { label: '已驳回', value: 'rejected' },
]

const handleStatusOptions = [
  { label: '处理中', value: 'processing' },
  { label: '已处理', value: 'resolved' },
  { label: '已驳回', value: 'rejected' },
]

const sceneOptions = [
  { label: '聊天', value: 'chat' },
  { label: '个人详情', value: 'profile' },
]

const statusMap = {
  pending: { type: 'warning', text: '待处理' },
  processing: { type: 'info', text: '处理中' },
  resolved: { type: 'success', text: '已处理' },
  rejected: { type: 'error', text: '已驳回' },
}

const sceneMap = {
  chat: '聊天',
  profile: '个人详情',
}

onMounted(() => {
  $table.value?.handleSearch()
})

function renderDate(value) {
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

function renderStatus(value) {
  const item = statusMap[value] || { type: 'default', text: value || '-' }
  return h(NTag, { type: item.type }, { default: () => item.text })
}

function statusText(value) {
  return statusMap[value]?.text || value || '-'
}

function statusType(value) {
  return statusMap[value]?.type || 'default'
}

function renderRisk(row) {
  if (row.target_risk_flag !== 'multiple_complaints') return '-'
  return h(NTag, { type: 'error' }, { default: () => '多次被投诉' })
}

async function fetchData(params = {}) {
  const res = await api.getComplaintList({
    page: params.page,
    page_size: params.page_size,
    complainant_id: params.complainant_id || undefined,
    target_user_id: params.target_user_id || undefined,
    status: params.status || '',
    scene: params.scene || '',
    keyword: params.keyword || '',
    start_time: params.start_time || undefined,
    end_time: params.end_time || undefined,
  })
  return {
    data: res.data || [],
    total: res.total || 0,
  }
}

async function openDetail(row) {
  if (!row?.id) return
  try {
    const res = await api.getComplaintDetail({ id: row.id })
    currentComplaint.value = res.data || row
    detailVisible.value = true
  } catch (error) {
    window.$message?.error(error?.message || '加载投诉详情失败')
  }
}

function openHandle(row) {
  if (!row?.id) return
  currentComplaint.value = row
  handleForm.id = row.id
  handleForm.status = row.status === 'pending' ? 'processing' : row.status || 'processing'
  if (handleForm.status === 'pending') handleForm.status = 'processing'
  handleForm.handle_remark = row.handle_remark || ''
  handleVisible.value = true
}

async function submitHandle() {
  if (!handleForm.id) return
  handleLoading.value = true
  try {
    await api.handleComplaint({
      id: handleForm.id,
      status: handleForm.status,
      handle_remark: handleForm.handle_remark || '',
    })
    window.$message?.success('处理成功')
    handleVisible.value = false
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '处理失败')
  } finally {
    handleLoading.value = false
  }
}

function viewTargetUser(row) {
  const userId = row?.target_user_id
  if (!userId) return
  router.push({ path: '/operation/app-user', query: { user_id: userId } })
}

function withStoppedClick(handler) {
  return (event) => {
    event?.stopPropagation?.()
    handler()
  }
}

const columns = [
  { title: '投诉ID', key: 'id', width: 90, align: 'center' },
  {
    title: '投诉人',
    key: 'complainant',
    width: 210,
    render(row) {
      return h('div', {}, [
        h('div', {}, `ID: ${row.complainant_id}`),
        h(
          'div',
          { class: 'sub' },
          `${row.complainant_nickname || '-'} / ${row.complainant_phone || '-'}`
        ),
      ])
    },
  },
  {
    title: '被投诉用户',
    key: 'target',
    width: 240,
    render(row) {
      return h('div', { class: 'target-user' }, [
        h('div', {}, `ID: ${row.target_user_id}`),
        h('div', { class: 'sub' }, `${row.target_nickname || '-'} / ${row.target_phone || '-'}`),
        h(
          NButton,
          {
            size: 'tiny',
            text: true,
            type: 'primary',
            onClick: withStoppedClick(() => viewTargetUser(row)),
          },
          { default: () => '查看用户' }
        ),
      ])
    },
  },
  { title: '累计被投诉次数', key: 'target_complaint_count', width: 130, align: 'center' },
  { title: '待处理投诉次数', key: 'target_pending_complaint_count', width: 130, align: 'center' },
  {
    title: '风险标识',
    key: 'target_risk_flag',
    width: 120,
    align: 'center',
    render: renderRisk,
  },
  {
    title: '来源',
    key: 'scene',
    width: 100,
    align: 'center',
    render(row) {
      return sceneMap[row.scene] || row.scene || '-'
    },
  },
  { title: '原因', key: 'reason', width: 130, ellipsis: { tooltip: true } },
  {
    title: '状态',
    key: 'status',
    width: 100,
    align: 'center',
    render(row) {
      return renderStatus(row.status)
    },
  },
  {
    title: '提交时间',
    key: 'created_at',
    width: 170,
    align: 'center',
    render(row) {
      return renderDate(row.created_at)
    },
  },
  {
    title: '处理时间',
    key: 'handled_at',
    width: 170,
    align: 'center',
    render(row) {
      return renderDate(row.handled_at)
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
          { size: 'small', secondary: true, onClick: withStoppedClick(() => openDetail(row)) },
          {
            default: () => '详情',
            icon: renderIcon('material-symbols:visibility-outline', { size: 16 }),
          }
        ),
        h(
          NButton,
          {
            size: 'small',
            type: 'primary',
            secondary: true,
            onClick: withStoppedClick(() => openHandle(row)),
          },
          {
            default: () => '处理',
            icon: renderIcon('material-symbols:fact-check-outline', { size: 16 }),
          }
        ),
      ])
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="投诉管理">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="fetchData"
      :scroll-x="1680"
    >
      <template #queryBar>
        <QueryBarItem label="投诉人ID" :label-width="70">
          <NInput v-model:value="queryItems.complainant_id" clearable placeholder="投诉人ID" />
        </QueryBarItem>
        <QueryBarItem label="被投诉ID" :label-width="70">
          <NInput v-model:value="queryItems.target_user_id" clearable placeholder="被投诉用户ID" />
        </QueryBarItem>
        <QueryBarItem label="状态" :label-width="50">
          <NSelect
            v-model:value="queryItems.status"
            clearable
            :options="statusOptions"
            style="width: 140px"
          />
        </QueryBarItem>
        <QueryBarItem label="来源" :label-width="50">
          <NSelect
            v-model:value="queryItems.scene"
            clearable
            :options="sceneOptions"
            style="width: 140px"
          />
        </QueryBarItem>
        <QueryBarItem label="关键词" :label-width="55">
          <NInput v-model:value="queryItems.keyword" clearable placeholder="原因或内容" />
        </QueryBarItem>
        <QueryBarItem label="提交时间" :label-width="70">
          <NDatePicker
            v-model:value="datetimeRange"
            type="datetimerange"
            clearable
            placeholder="请选择提交时间范围"
            @update:value="handleDateRangeChange"
          />
        </QueryBarItem>
      </template>
    </CrudTable>

    <NModal v-model:show="detailVisible" preset="card" title="投诉详情" style="width: 760px">
      <div v-if="currentComplaint" class="detail">
        <div class="detail-header">
          <div>
            <div class="detail-title">投诉 {{ currentComplaint.id }}</div>
            <div class="sub">{{ renderDate(currentComplaint.created_at) }}</div>
          </div>
          <NTag :type="statusType(currentComplaint.status)">
            {{ statusText(currentComplaint.status) }}
          </NTag>
        </div>
        <div class="detail-meta">
          <div>
            投诉人：ID {{ currentComplaint.complainant_id }} /
            {{ currentComplaint.complainant_nickname || '-' }}
          </div>
          <div>
            被投诉用户：ID {{ currentComplaint.target_user_id }} /
            {{ currentComplaint.target_nickname || '-' }}
            <NButton text type="primary" size="tiny" @click.stop="viewTargetUser(currentComplaint)"
              >查看用户</NButton
            >
          </div>
          <div>累计被投诉次数：{{ currentComplaint.target_complaint_count || 0 }}</div>
          <div>待处理投诉次数：{{ currentComplaint.target_pending_complaint_count || 0 }}</div>
          <div>
            风险标识：{{
              currentComplaint.target_risk_flag === 'multiple_complaints' ? '多次被投诉' : '-'
            }}
          </div>
          <div>来源：{{ sceneMap[currentComplaint.scene] || currentComplaint.scene || '-' }}</div>
          <div>原因：{{ currentComplaint.reason || '-' }}</div>
          <div>处理时间：{{ renderDate(currentComplaint.handled_at) }}</div>
        </div>
        <div class="detail-block">
          <div class="detail-label">投诉内容</div>
          <div class="detail-content">{{ currentComplaint.content || '-' }}</div>
        </div>
        <div class="detail-block">
          <div class="detail-label">处理备注</div>
          <div class="detail-content">{{ currentComplaint.handle_remark || '-' }}</div>
        </div>
      </div>
    </NModal>

    <NModal v-model:show="handleVisible" preset="card" title="处理投诉" style="width: 520px">
      <NForm label-placement="left" label-width="80">
        <NFormItem label="处理状态">
          <NSelect v-model:value="handleForm.status" :options="handleStatusOptions" />
        </NFormItem>
        <NFormItem label="处理备注">
          <NInput
            v-model:value="handleForm.handle_remark"
            type="textarea"
            :autosize="{ minRows: 4, maxRows: 8 }"
            placeholder="请输入处理备注"
          />
        </NFormItem>
      </NForm>
      <div class="notice">
        处理投诉不会自动封禁用户；如需处置账号，请点击“查看用户”进入用户管理。
      </div>
      <template #action>
        <NButton @click.stop="handleVisible = false">取消</NButton>
        <NButton
          type="primary"
          :loading="handleLoading"
          style="margin-left: 8px"
          @click.stop="submitHandle"
        >
          保存处理结果
        </NButton>
      </template>
    </NModal>
  </CommonPage>
</template>

<style scoped>
.sub {
  color: #8b8f99;
  font-size: 12px;
  margin-top: 2px;
}

.target-user {
  display: flex;
  flex-direction: column;
  gap: 2px;
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
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px 16px;
  color: #4e5969;
  font-size: 13px;
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

.notice {
  color: #8b8f99;
  font-size: 13px;
  line-height: 1.6;
  background: #f7f8fb;
  border-radius: 8px;
  padding: 10px 12px;
}
</style>
