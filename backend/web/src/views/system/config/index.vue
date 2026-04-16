<script setup>
import { h, onMounted, ref } from 'vue'
import {
  NButton,
  NCard,
  NForm,
  NFormItem,
  NInput,
  NInputNumber,
  NPopconfirm,
  NSpace,
} from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudModal from '@/components/table/CrudModal.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import TheIcon from '@/components/icon/TheIcon.vue'
import { renderIcon } from '@/utils'
import { useCRUD } from '@/composables'
import api from '@/api'

defineOptions({ name: '系统配置' })

const $table = ref(null)
const queryItems = ref({})
const allConfigRows = ref([])

const tokenLoading = ref(false)
const imLoading = ref(false)
const rtcLoading = ref(false)
const protectLoading = ref(false)

const tokenForm = ref({
  coin_name: '金币',
  diamond_name: '钻石',
})

const imForm = ref({
  im_sdk_app_id: null,
  im_secret_key: '',
})

const rtcForm = ref({
  rtc_app_id: '',
  rtc_app_certificate: '',
})

const protectForm = ref({
  reject_inbound_protect_seconds: 5,
  reject_pair_protect_seconds: 5,
})

const {
  modalVisible,
  modalTitle,
  modalLoading,
  handleSave,
  modalForm,
  modalFormRef,
  handleEdit,
  handleDelete,
  handleAdd,
} = useCRUD({
  name: '系统配置',
  initForm: {},
  doCreate: api.createSystemConfig,
  doUpdate: api.updateSystemConfig,
  doDelete: api.deleteSystemConfig,
  refresh: async () => {
    await loadAllConfigs()
    $table.value?.handleSearch()
  },
})

const modalRules = {
  cfg_key: [
    {
      required: true,
      message: '请输入配置键',
      trigger: ['input', 'blur'],
    },
  ],
  cfg_value: [
    {
      required: true,
      message: '请输入配置值',
      trigger: ['input', 'blur'],
    },
  ],
}

const columns = [
  { title: 'ID', key: 'id', width: 80, align: 'center' },
  { title: '配置键', key: 'cfg_key', minWidth: 260, align: 'center' },
  { title: '配置值', key: 'cfg_value', minWidth: 220, align: 'center' },
  { title: '说明', key: 'description', minWidth: 300, align: 'center' },
  {
    title: '操作',
    key: 'actions',
    width: 180,
    align: 'center',
    fixed: 'right',
    render(row) {
      return [
        h(
          NButton,
          {
            size: 'small',
            type: 'primary',
            style: 'margin-right: 8px;',
            onClick: () => handleEdit(row),
          },
          {
            default: () => '编辑',
            icon: renderIcon('material-symbols:edit', { size: 16 }),
          }
        ),
        h(
          NPopconfirm,
          {
            onPositiveClick: () => handleDelete({ cfg_id: row.id }, false),
          },
          {
            trigger: () =>
              h(
                NButton,
                { size: 'small', type: 'error' },
                {
                  default: () => '删除',
                  icon: renderIcon('material-symbols:delete-outline', { size: 16 }),
                }
              ),
            default: () => h('div', {}, '确定删除该配置吗?'),
          }
        ),
      ]
    },
  },
]

onMounted(async () => {
  $table.value?.handleSearch()
  await loadAllConfigs()
})

async function loadAllConfigs() {
  try {
    const res = await api.getSystemConfigList({ page: 1, page_size: 500 })
    const rows = res.data || []
    allConfigRows.value = rows

    tokenForm.value.coin_name = findValue('coin_name', '金币')
    tokenForm.value.diamond_name = findValue('diamond_name', '钻石')

    imForm.value.im_sdk_app_id = normalizeNullablePositiveInt(findValue('im_sdk_app_id', ''))
    imForm.value.im_secret_key = findValue('im_secret_key', '')

    rtcForm.value.rtc_app_id = findValue('rtc_app_id', '')
    rtcForm.value.rtc_app_certificate = findValue('rtc_app_certificate', '')

    protectForm.value.reject_inbound_protect_seconds = normalizeSeconds(
      findValue('call_reject_inbound_protect_seconds', '5'),
      5
    )
    protectForm.value.reject_pair_protect_seconds = normalizeSeconds(
      findValue('call_reject_pair_protect_seconds', '5'),
      5
    )
  } catch (_) {}
}

function findRow(cfgKey) {
  return allConfigRows.value.find((r) => r.cfg_key === cfgKey)
}

function findValue(cfgKey, fallback = '') {
  const row = findRow(cfgKey)
  if (!row) return fallback
  return (row.cfg_value ?? fallback).toString()
}

function normalizeSeconds(raw, fallback = 5) {
  const n = Number(raw)
  if (!Number.isFinite(n)) return fallback
  if (n < 0) return 0
  if (n > 600) return 600
  return Math.floor(n)
}

function normalizeNullablePositiveInt(raw) {
  const n = Number(raw)
  if (!Number.isFinite(n) || n <= 0) return null
  return Math.floor(n)
}

async function upsertConfig(cfgKey, cfgValue, description) {
  const existing = findRow(cfgKey)
  if (existing) {
    await api.updateSystemConfig({
      id: existing.id,
      cfg_key: cfgKey,
      cfg_value: cfgValue,
      description: existing.description || description,
    })
    return
  }
  await api.createSystemConfig({
    cfg_key: cfgKey,
    cfg_value: cfgValue,
    description,
  })
}

async function saveTokenConfigs() {
  tokenLoading.value = true
  try {
    await upsertConfig('coin_name', tokenForm.value.coin_name.trim() || '金币', '代币名称：金币')
    await upsertConfig('diamond_name', tokenForm.value.diamond_name.trim() || '钻石', '代币名称：钻石')
    await loadAllConfigs()
    $table.value?.handleSearch()
    $message.success('基础代币配置已保存')
  } catch (_) {
    $message.error('保存失败，请稍后重试')
  } finally {
    tokenLoading.value = false
  }
}

async function saveImConfigs() {
  imLoading.value = true
  try {
    const sdkId = imForm.value.im_sdk_app_id ? String(imForm.value.im_sdk_app_id) : ''
    await upsertConfig('im_sdk_app_id', sdkId, '腾讯IM SDK AppID')
    await upsertConfig('im_secret_key', imForm.value.im_secret_key.trim(), '腾讯IM SecretKey')
    await loadAllConfigs()
    $table.value?.handleSearch()
    $message.success('IM 配置已保存')
  } catch (_) {
    $message.error('保存失败，请稍后重试')
  } finally {
    imLoading.value = false
  }
}

async function saveRtcConfigs() {
  rtcLoading.value = true
  try {
    await upsertConfig('rtc_app_id', rtcForm.value.rtc_app_id.trim(), '声网 RTC App ID')
    await upsertConfig(
      'rtc_app_certificate',
      rtcForm.value.rtc_app_certificate.trim(),
      '声网 RTC App Certificate'
    )
    await loadAllConfigs()
    $table.value?.handleSearch()
    $message.success('RTC 配置已保存')
  } catch (_) {
    $message.error('保存失败，请稍后重试')
  } finally {
    rtcLoading.value = false
  }
}

async function saveProtectConfigs() {
  protectLoading.value = true
  try {
    const inbound = normalizeSeconds(protectForm.value.reject_inbound_protect_seconds, 5)
    const pair = normalizeSeconds(protectForm.value.reject_pair_protect_seconds, 5)

    await upsertConfig(
      'call_reject_inbound_protect_seconds',
      String(inbound),
      '拒绝后禁止呼入保护时间（秒）'
    )
    await upsertConfig(
      'call_reject_pair_protect_seconds',
      String(pair),
      '拒绝后禁止同一主叫再次呼叫保护时间（秒）'
    )

    await loadAllConfigs()
    $table.value?.handleSearch()
    $message.success('通话保护配置已保存')
  } catch (_) {
    $message.error('保存失败，请稍后重试')
  } finally {
    protectLoading.value = false
  }
}
</script>

<template>
  <CommonPage show-footer title="系统配置">
    <template #action>
      <NButton type="primary" @click="handleAdd">
        <TheIcon icon="material-symbols:add" :size="18" class="mr-5" />新建配置
      </NButton>
    </template>

    <NSpace vertical :size="16" class="mb-20">
      <NCard title="基础配置（代币名称）">
        <NForm label-placement="left" label-align="left" :label-width="160" :model="tokenForm">
          <NFormItem label="金币名称 coin_name">
            <NInput v-model:value="tokenForm.coin_name" placeholder="例如：金币" />
          </NFormItem>
          <NFormItem label="钻石名称 diamond_name">
            <NInput v-model:value="tokenForm.diamond_name" placeholder="例如：钻石" />
          </NFormItem>
        </NForm>
        <NButton type="primary" :loading="tokenLoading" @click="saveTokenConfigs">保存基础配置</NButton>
      </NCard>

      <NCard title="IM 配置（腾讯云）">
        <NForm label-placement="left" label-align="left" :label-width="180" :model="imForm">
          <NFormItem label="IM SDK AppID im_sdk_app_id">
            <NInputNumber v-model:value="imForm.im_sdk_app_id" :min="1" placeholder="请输入数字 AppID" />
          </NFormItem>
          <NFormItem label="IM SecretKey im_secret_key">
            <NInput
              v-model:value="imForm.im_secret_key"
              type="password"
              show-password-on="mousedown"
              placeholder="请输入 IM SecretKey"
            />
          </NFormItem>
        </NForm>
        <NButton type="primary" :loading="imLoading" @click="saveImConfigs">保存 IM 配置</NButton>
      </NCard>

      <NCard title="RTC 配置（声网）">
        <NForm label-placement="left" label-align="left" :label-width="220" :model="rtcForm">
          <NFormItem label="RTC App ID rtc_app_id">
            <NInput v-model:value="rtcForm.rtc_app_id" placeholder="请输入声网 App ID" />
          </NFormItem>
          <NFormItem label="RTC App Certificate rtc_app_certificate">
            <NInput
              v-model:value="rtcForm.rtc_app_certificate"
              type="password"
              show-password-on="mousedown"
              placeholder="请输入声网 App Certificate"
            />
          </NFormItem>
        </NForm>
        <NButton type="primary" :loading="rtcLoading" @click="saveRtcConfigs">保存 RTC 配置</NButton>
      </NCard>

      <NCard title="通话保护配置">
        <NForm
          label-placement="left"
          label-align="left"
          :label-width="260"
          :model="protectForm"
        >
          <NFormItem label="拒绝后禁止呼入（秒） call_reject_inbound_protect_seconds">
            <NInputNumber
              v-model:value="protectForm.reject_inbound_protect_seconds"
              :min="0"
              :max="600"
              placeholder="例如 5"
            />
          </NFormItem>
          <NFormItem label="拒绝后禁止同一用户再次呼叫（秒） call_reject_pair_protect_seconds">
            <NInputNumber
              v-model:value="protectForm.reject_pair_protect_seconds"
              :min="0"
              :max="600"
              placeholder="例如 5"
            />
          </NFormItem>
        </NForm>
        <NButton type="primary" :loading="protectLoading" @click="saveProtectConfigs">
          保存通话保护配置
        </NButton>
      </NCard>
    </NSpace>

    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="api.getSystemConfigList"
    >
      <template #queryBar>
        <QueryBarItem label="配置键" :label-width="60">
          <NInput
            v-model:value="queryItems.cfg_key"
            clearable
            type="text"
            placeholder="请输入配置键"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
      </template>
    </CrudTable>

    <CrudModal
      v-model:visible="modalVisible"
      :title="modalTitle"
      :loading="modalLoading"
      @save="handleSave"
    >
      <NForm
        ref="modalFormRef"
        label-placement="left"
        label-align="left"
        :label-width="80"
        :model="modalForm"
        :rules="modalRules"
      >
        <NFormItem label="配置键" path="cfg_key">
          <NInput v-model:value="modalForm.cfg_key" clearable placeholder="请输入配置键" />
        </NFormItem>
        <NFormItem label="配置值" path="cfg_value">
          <NInput v-model:value="modalForm.cfg_value" clearable placeholder="请输入配置值" />
        </NFormItem>
        <NFormItem label="说明" path="description">
          <NInput
            v-model:value="modalForm.description"
            type="textarea"
            clearable
            placeholder="请输入说明"
          />
        </NFormItem>
      </NForm>
    </CrudModal>
  </CommonPage>
</template>
