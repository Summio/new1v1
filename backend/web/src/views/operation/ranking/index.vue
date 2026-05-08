<script setup>
import { h, onMounted, reactive, ref } from 'vue'
import { NAvatar, NButton, NInputNumber, NSelect, NSpace, NTag } from 'naive-ui'

import api from '@/api'
import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import { formatDate } from '@/utils'

defineOptions({ name: '排行榜' })

const $table = ref(null)
const queryItems = ref({
  board: 'charm',
  period: 'day',
})
const configForm = reactive({
  appDisplayLimit: 20,
})
const configLoading = ref(false)
const refreshLoading = ref(false)

const boardOptions = [
  { label: '魅力榜', value: 'charm' },
  { label: '富豪榜', value: 'wealth' },
  { label: '邀请榜', value: 'invite' },
]
const periodOptions = [
  { label: '日榜', value: 'day' },
  { label: '周榜', value: 'week' },
  { label: '月榜', value: 'month' },
]
const boardMap = {
  charm: { type: 'error', text: '魅力榜' },
  wealth: { type: 'warning', text: '富豪榜' },
  invite: { type: 'info', text: '邀请榜' },
}
const periodMap = {
  day: '日榜',
  week: '周榜',
  month: '月榜',
}

onMounted(async () => {
  await loadConfig()
  $table.value?.handleSearch()
})

function renderBoard(board) {
  const target = boardMap[board] || { type: 'default', text: board || '-' }
  return h(NTag, { type: target.type }, { default: () => target.text })
}

function renderDate(value) {
  return value ? formatDate(value, 'YYYY-MM-DD HH:mm:ss') : '-'
}

async function loadConfig() {
  try {
    const res = await api.getRankingConfig()
    const value = Number(res?.data?.app_display_limit || 20)
    configForm.appDisplayLimit = Number.isFinite(value) ? value : 20
  } catch (error) {
    window.$message?.error(error?.message || '获取排行榜配置失败')
  }
}

async function saveConfig() {
  const value = Number(configForm.appDisplayLimit)
  if (!Number.isInteger(value) || value < 1 || value > 100) {
    window.$message?.warning('App展示数量必须是1-100之间的整数')
    return
  }
  configLoading.value = true
  try {
    await api.updateRankingConfig({ app_display_limit: value })
    window.$message?.success('保存成功')
  } catch (error) {
    window.$message?.error(error?.message || '保存失败')
  } finally {
    configLoading.value = false
  }
}

async function refreshRanking() {
  refreshLoading.value = true
  try {
    await api.refreshRanking({
      board: queryItems.value.board || 'charm',
      period: queryItems.value.period || 'day',
    })
    window.$message?.success('刷新成功')
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '刷新失败')
  } finally {
    refreshLoading.value = false
  }
}

async function fetchData(params = {}) {
  const res = await api.getRankingList({
    page: params.page,
    page_size: params.page_size,
    board: params.board || 'charm',
    period: params.period || 'day',
    user_id: params.user_id || undefined,
  })
  return {
    data: res.rows || [],
    total: res.total || 0,
  }
}

const columns = [
  { title: '排名', key: 'rank', width: 80, align: 'center' },
  {
    title: '用户',
    key: 'user',
    minWidth: 220,
    render(row) {
      return h('div', { class: 'user-cell' }, [
        h(NAvatar, {
          round: true,
          size: 42,
          src: row.avatar || undefined,
        }),
        h('div', { class: 'user-meta' }, [
          h('div', { class: 'name' }, row.nickname || '-'),
          h('div', { class: 'sub' }, `ID: ${row.user_id}`),
        ]),
      ])
    },
  },
  {
    title: '榜单',
    key: 'board',
    width: 100,
    align: 'center',
    render(row) {
      return renderBoard(row.board)
    },
  },
  {
    title: '周期',
    key: 'period',
    width: 90,
    align: 'center',
    render(row) {
      return periodMap[row.period] || row.period || '-'
    },
  },
  {
    title: '真实分数',
    key: 'score_text',
    width: 130,
    align: 'center',
    render(row) {
      return row.score_text || `${row.score ?? 0}`
    },
  },
  {
    title: '统计开始',
    key: 'period_start',
    width: 170,
    align: 'center',
    render(row) {
      return renderDate(row.period_start)
    },
  },
  {
    title: '统计结束',
    key: 'period_end',
    width: 170,
    align: 'center',
    render(row) {
      return renderDate(row.period_end)
    },
  },
  {
    title: '快照时间',
    key: 'computed_at',
    width: 170,
    align: 'center',
    render(row) {
      return renderDate(row.computed_at)
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="排行榜">
    <div class="ranking-config">
      <NSpace align="center" :size="12">
        <span class="config-label">App展示数量</span>
        <NInputNumber
          v-model:value="configForm.appDisplayLimit"
          :min="1"
          :max="100"
          :step="1"
          style="width: 140px"
        />
        <NButton type="primary" :loading="configLoading" @click="saveConfig">保存配置</NButton>
        <NButton :loading="refreshLoading" @click="refreshRanking">刷新当前榜单</NButton>
      </NSpace>
    </div>

    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="fetchData"
      :scroll-x="1210"
    >
      <template #queryBar>
        <QueryBarItem label="榜单" :label-width="45">
          <NSelect v-model:value="queryItems.board" style="width: 140px" :options="boardOptions" />
        </QueryBarItem>
        <QueryBarItem label="周期" :label-width="45">
          <NSelect
            v-model:value="queryItems.period"
            style="width: 120px"
            :options="periodOptions"
          />
        </QueryBarItem>
        <QueryBarItem label="用户ID" :label-width="55">
          <NInputNumber
            v-model:value="queryItems.user_id"
            clearable
            :show-button="false"
            placeholder="请输入用户ID"
            style="width: 160px"
          />
        </QueryBarItem>
      </template>
    </CrudTable>
  </CommonPage>
</template>

<style scoped>
.ranking-config {
  margin-bottom: 14px;
  padding: 12px 16px;
  background: #fff;
  border-radius: 8px;
}

.config-label {
  color: #333;
  font-weight: 600;
}

.user-cell {
  display: flex;
  align-items: center;
  gap: 10px;
}

.user-meta {
  min-width: 0;
}

.name {
  max-width: 150px;
  overflow: hidden;
  color: #333;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sub {
  margin-top: 2px;
  color: #8b8f99;
  font-size: 12px;
}
</style>
