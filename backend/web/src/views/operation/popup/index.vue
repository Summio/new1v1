<script setup>
import { computed, h, onMounted, ref } from 'vue'
import {
  NAlert,
  NButton,
  NDatePicker,
  NForm,
  NFormItem,
  NInput,
  NInputNumber,
  NModal,
  NPopconfirm,
  NRadio,
  NRadioGroup,
  NSelect,
  NSpace,
  NTag,
} from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate, renderIcon } from '@/utils'

defineOptions({ name: '弹窗提示' })

const $table = ref(null)
const queryItems = ref({ keyword: '', type: '', status: '', send_mode: '' })
const modalVisible = ref(false)
const detailVisible = ref(false)
const detail = ref(null)
const estimatedCount = ref(null)
const editingId = ref(null)
const modalTitle = computed(() => (editingId.value ? '编辑弹窗提示' : '新建弹窗提示'))

const typeOptions = [
  { label: '平台公告', value: 'announcement' },
  { label: '账户提示', value: 'account' },
  { label: '审核提示', value: 'review' },
  { label: '互动提示', value: 'interaction' },
]
const statusOptions = [
  { label: '草稿', value: 'draft' },
  { label: '待发送', value: 'scheduled' },
  { label: '运行中', value: 'running' },
  { label: '已暂停', value: 'paused' },
  { label: '已完成', value: 'completed' },
  { label: '已取消', value: 'cancelled' },
]
const sendModeOptions = [
  { label: '立即发送', value: 'immediate' },
  { label: '一次性定时', value: 'once' },
  { label: '周期重复', value: 'repeat' },
]
const repeatTypeOptions = [
  { label: '每日', value: 'daily' },
  { label: '每周', value: 'weekly' },
  { label: '每月', value: 'monthly' },
]

const form = ref(defaultForm())

function defaultForm() {
  return {
    title: '',
    content: '',
    type: 'announcement',
    status: 'scheduled',
    send_mode: 'immediate',
    target_mode: 'all',
    target_user_ids: '',
    target_filters: {},
    publish_at: null,
    repeat_type: 'daily',
    repeat_time: '10:00',
    repeat_weekday: 0,
    repeat_month_day: 1,
    end_at: null,
    max_runs: null,
  }
}

onMounted(() => {
  $table.value?.handleSearch()
})

function renderDate(value) {
  return value ? formatDate(value, 'YYYY-MM-DD HH:mm:ss') : '-'
}

function labelOf(options, value) {
  return options.find((item) => item.value === value)?.label || value || '-'
}

async function fetchData(params = {}) {
  const res = await api.getSystemPopupList({
    page: params.page,
    page_size: params.page_size,
    keyword: params.keyword || '',
    type: params.type || '',
    status: params.status || '',
    send_mode: params.send_mode || '',
  })
  return { data: res.data || [], total: res.total || 0 }
}

function openCreate() {
  form.value = defaultForm()
  editingId.value = null
  estimatedCount.value = null
  modalVisible.value = true
}

function toDatePickerValue(value) {
  if (!value) return null
  const time = new Date(value).getTime()
  return Number.isNaN(time) ? null : time
}

function openEdit(row) {
  editingId.value = row.id
  estimatedCount.value = null
  form.value = {
    ...defaultForm(),
    ...row,
    target_user_ids: Array.isArray(row.target_user_ids)
      ? row.target_user_ids.join(',')
      : row.target_user_ids || '',
    target_filters: row.target_filters || {},
    publish_at: toDatePickerValue(row.publish_at),
    end_at: toDatePickerValue(row.end_at),
  }
  modalVisible.value = true
}

async function openDetail(row) {
  try {
    const res = await api.getSystemPopupDetail({ id: row.id })
    detail.value = res.data || row
    detailVisible.value = true
  } catch (error) {
    window.$message?.error(error?.message || '获取详情失败')
  }
}

function buildPayload() {
  const payload = { ...form.value, target_filters: { ...(form.value.target_filters || {}) } }
  if (typeof payload.publish_at === 'number') {
    payload.publish_at = new Date(payload.publish_at).toISOString()
  }
  if (typeof payload.end_at === 'number') {
    payload.end_at = new Date(payload.end_at).toISOString()
  }
  if (payload.target_mode !== 'user_ids') payload.target_user_ids = null
  if (payload.target_mode !== 'filter') payload.target_filters = null
  if (payload.send_mode !== 'once') payload.publish_at = null
  if (payload.send_mode !== 'repeat') {
    payload.repeat_type = null
    payload.repeat_time = null
    payload.repeat_weekday = null
    payload.repeat_month_day = null
    payload.end_at = null
    payload.max_runs = null
  }
  return payload
}

async function estimateTargetCount() {
  try {
    const payload = buildPayload()
    const res = await api.estimateSystemPopupTargetCount({
      target_mode: payload.target_mode,
      target_user_ids: payload.target_user_ids,
      target_filters: payload.target_filters,
    })
    estimatedCount.value = res.data?.count ?? 0
  } catch (error) {
    window.$message?.error(error?.message || '当前在线可触达人数计算失败')
  }
}

async function submitTask(asDraft = false) {
  const payload = buildPayload()
  if (editingId.value) payload.id = editingId.value
  if (!editingId.value && !asDraft) payload.status = 'scheduled'
  if (asDraft) payload.status = 'draft'
  if (!payload.title?.trim()) {
    window.$message?.warning('请填写标题')
    return
  }
  if (!payload.content?.trim()) {
    window.$message?.warning('请填写正文')
    return
  }
  if (payload.send_mode === 'repeat' && !payload.end_at && !payload.max_runs) {
    window.$message?.warning('周期重复必须填写结束时间或最大发送次数')
    return
  }
  try {
    if (editingId.value) {
      await api.updateSystemPopup(payload)
    } else {
      await api.createSystemPopup(payload)
    }
    window.$message?.success(editingId.value ? '保存成功' : asDraft ? '草稿已保存' : '创建成功')
    modalVisible.value = false
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '保存失败')
  }
}

async function doAction(row, action, successText) {
  try {
    await api[action]({ id: row.id })
    window.$message?.success(successText)
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '操作失败')
  }
}

async function handleDelete(row) {
  try {
    await api.deleteSystemPopup({ id: row.id })
    window.$message?.success('删除成功')
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '删除失败')
  }
}

const columns = [
  { title: 'ID', key: 'id', width: 80, align: 'center' },
  { title: '标题', key: 'title', minWidth: 150, ellipsis: { tooltip: true } },
  { title: '正文摘要', key: 'content', minWidth: 220, ellipsis: { tooltip: true } },
  {
    title: '类型',
    key: 'type',
    width: 110,
    render(row) {
      return h(NTag, { size: 'small', type: 'info' }, () => labelOf(typeOptions, row.type))
    },
  },
  {
    title: '发送模式',
    key: 'send_mode',
    width: 120,
    render: (row) => labelOf(sendModeOptions, row.send_mode),
  },
  {
    title: '状态',
    key: 'status',
    width: 100,
    render(row) {
      return h(NTag, { size: 'small' }, () => labelOf(statusOptions, row.status))
    },
  },
  { title: '目标范围', key: 'target_mode', width: 110 },
  {
    title: '当前在线可触达人数',
    key: 'estimated_count',
    width: 160,
    align: 'center',
    render: (row) => row.estimated_count ?? '-',
  },
  {
    title: '已推送人数',
    key: 'pushed_count',
    width: 110,
    align: 'center',
    render: (row) => row.pushed_count ?? 0,
  },
  {
    title: '已确认人数',
    key: 'ack_count',
    width: 110,
    align: 'center',
    render: (row) => row.ack_count ?? 0,
  },
  {
    title: '下次发送时间',
    key: 'next_run_at',
    width: 180,
    render: (row) => renderDate(row.next_run_at),
  },
  { title: '已发送次数', key: 'run_count', width: 110, align: 'center' },
  { title: '创建时间', key: 'created_at', width: 180, render: (row) => renderDate(row.created_at) },
  {
    title: '操作',
    key: 'actions',
    width: 270,
    fixed: 'right',
    render(row) {
      const actions = [
        h(
          NButton,
          { size: 'small', secondary: true, onClick: () => openDetail(row) },
          { default: () => '查看' }
        ),
      ]
      if (row.status === 'running') {
        actions.push(
          h(
            NButton,
            {
              size: 'small',
              secondary: true,
              onClick: () => doAction(row, 'pauseSystemPopup', '已暂停'),
            },
            { default: () => '暂停' }
          )
        )
      }
      if (row.status === 'paused') {
        actions.push(
          h(
            NButton,
            {
              size: 'small',
              secondary: true,
              onClick: () => doAction(row, 'resumeSystemPopup', '已恢复'),
            },
            { default: () => '恢复' }
          )
        )
      }
      if (['draft', 'scheduled', 'paused'].includes(row.status)) {
        actions.push(
          h(
            NButton,
            { size: 'small', secondary: true, onClick: () => openEdit(row) },
            { default: () => '编辑' }
          )
        )
      }
      if (['draft', 'scheduled'].includes(row.status)) {
        actions.push(
          h(
            NButton,
            {
              size: 'small',
              type: 'primary',
              secondary: true,
              onClick: () => doAction(row, 'publishSystemPopup', '已发布'),
            },
            { default: () => '发布' }
          )
        )
      }
      if (!['completed', 'cancelled'].includes(row.status)) {
        actions.push(
          h(
            NButton,
            {
              size: 'small',
              secondary: true,
              onClick: () => doAction(row, 'cancelSystemPopup', '已取消'),
            },
            { default: () => '取消' }
          )
        )
      }
      if ((row.run_count || 0) <= 0) {
        actions.push(
          h(
            NPopconfirm,
            { onPositiveClick: () => handleDelete(row) },
            {
              trigger: () =>
                h(
                  NButton,
                  { size: 'small', type: 'error', secondary: true },
                  { default: () => '删除' }
                ),
              default: () => '确认删除这个未发送任务？',
            }
          )
        )
      }
      return h(NSpace, { size: 8 }, () => actions)
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="弹窗提示">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="fetchData"
      :scroll-x="1900"
    >
      <template #queryBar>
        <QueryBarItem label="关键词" :label-width="60">
          <NInput v-model:value="queryItems.keyword" clearable placeholder="标题或正文关键词" />
        </QueryBarItem>
        <QueryBarItem label="类型" :label-width="45" :content-width="140">
          <NSelect
            v-model:value="queryItems.type"
            clearable
            :options="typeOptions"
            placeholder="全部"
          />
        </QueryBarItem>
        <QueryBarItem label="状态" :label-width="45" :content-width="140">
          <NSelect
            v-model:value="queryItems.status"
            clearable
            :options="statusOptions"
            placeholder="全部"
          />
        </QueryBarItem>
        <QueryBarItem label="发送模式" :label-width="70" :content-width="160">
          <NSelect
            v-model:value="queryItems.send_mode"
            clearable
            :options="sendModeOptions"
            placeholder="全部"
          />
        </QueryBarItem>
        <QueryBarItem :label-width="0" :content-width="120">
          <NButton type="primary" @click="openCreate">
            <template #icon>
              <component :is="renderIcon('material-symbols:add-rounded')" />
            </template>
            新建弹窗
          </NButton>
        </QueryBarItem>
      </template>
    </CrudTable>

    <NModal v-model:show="modalVisible" preset="card" :title="modalTitle" style="width: 840px">
      <NAlert type="info" :bordered="false" style="margin-bottom: 16px">
        弹窗仅在线 WebSocket 推送，离线用户不会补发；当前在线可触达人数以计算当刻为准。
      </NAlert>
      <NForm :model="form" label-placement="left" label-width="120">
        <NFormItem label="标题">
          <NInput
            v-model:value="form.title"
            maxlength="50"
            show-count
            placeholder="请输入弹窗标题"
          />
        </NFormItem>
        <NFormItem label="正文">
          <NInput v-model:value="form.content" type="textarea" :autosize="{ minRows: 5 }" />
        </NFormItem>
        <NFormItem label="弹窗类型">
          <NSelect v-model:value="form.type" :options="typeOptions" />
        </NFormItem>
        <NFormItem label="目标范围">
          <NRadioGroup v-model:value="form.target_mode">
            <NRadio value="all">全体</NRadio>
            <NRadio value="user_ids">指定用户ID</NRadio>
            <NRadio value="filter">条件筛选</NRadio>
          </NRadioGroup>
        </NFormItem>
        <NFormItem v-if="form.target_mode === 'user_ids'" label="用户ID">
          <NInput v-model:value="form.target_user_ids" placeholder="多个用户ID用英文逗号分隔" />
        </NFormItem>
        <template v-if="form.target_mode === 'filter'">
          <NFormItem label="性别">
            <NSelect
              v-model:value="form.target_filters.gender"
              clearable
              :options="[
                { label: '男', value: 'male' },
                { label: '女', value: 'female' },
              ]"
            />
          </NFormItem>
          <NFormItem label="真人认证">
            <NSelect
              v-model:value="form.target_filters.is_certified_user"
              clearable
              :options="[
                { label: '已认证', value: true },
                { label: '未认证', value: false },
              ]"
            />
          </NFormItem>
        </template>
        <NFormItem label="当前在线可触达人数">
          <NSpace align="center">
            <NButton secondary @click="estimateTargetCount">计算</NButton>
            <span>{{ estimatedCount === null ? '未计算' : `${estimatedCount} 人` }}</span>
          </NSpace>
        </NFormItem>
        <NFormItem label="发送模式">
          <NSelect v-model:value="form.send_mode" :options="sendModeOptions" />
        </NFormItem>
        <NFormItem v-if="form.send_mode === 'once'" label="发布时间">
          <NDatePicker v-model:value="form.publish_at" type="datetime" clearable />
        </NFormItem>
        <template v-if="form.send_mode === 'repeat'">
          <NFormItem label="周期类型">
            <NSelect v-model:value="form.repeat_type" :options="repeatTypeOptions" />
          </NFormItem>
          <NFormItem label="发送时间">
            <NInput v-model:value="form.repeat_time" placeholder="10:00" />
          </NFormItem>
          <NFormItem v-if="form.repeat_type === 'weekly'" label="周几">
            <NInputNumber v-model:value="form.repeat_weekday" :min="0" :max="6" />
          </NFormItem>
          <NFormItem v-if="form.repeat_type === 'monthly'" label="每月几号">
            <NInputNumber v-model:value="form.repeat_month_day" :min="1" :max="31" />
          </NFormItem>
          <NFormItem label="结束时间">
            <NDatePicker v-model:value="form.end_at" type="datetime" clearable />
          </NFormItem>
          <NFormItem label="最大发送次数">
            <NInputNumber v-model:value="form.max_runs" :min="1" clearable />
          </NFormItem>
        </template>
      </NForm>
      <template #footer>
        <NSpace justify="end">
          <NButton v-if="!editingId" @click="submitTask(true)">保存草稿</NButton>
          <NButton type="primary" @click="submitTask(false)">{{
            editingId ? '保存' : '提交'
          }}</NButton>
        </NSpace>
      </template>
    </NModal>

    <NModal v-model:show="detailVisible" preset="card" title="弹窗详情" style="width: 760px">
      <div v-if="detail" class="detail">
        <h3>{{ detail.title }}</h3>
        <div class="sub">
          {{ labelOf(typeOptions, detail.type) }} / {{ renderDate(detail.created_at) }}
        </div>
        <pre>{{ detail.content }}</pre>
      </div>
    </NModal>
  </CommonPage>
</template>

<style scoped>
.sub {
  color: #8b8f99;
  font-size: 13px;
}

.detail {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.detail h3 {
  margin: 0;
  color: #1f2329;
}

pre {
  white-space: pre-wrap;
  line-height: 1.6;
  background: #f7f8fb;
  border-radius: 8px;
  padding: 12px;
  color: #1f2329;
}
</style>
