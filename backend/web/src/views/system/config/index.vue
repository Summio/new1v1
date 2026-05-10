<script setup>
import { computed, h, onMounted, ref } from 'vue'
import {
  NButton,
  NDataTable,
  NInput,
  NInputNumber,
  NPopconfirm,
  NSpace,
  NSwitch,
  NTag,
  useMessage,
} from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import api from '@/api'

defineOptions({ name: '系统配置' })

const message = useMessage()
const loading = ref(false)
const savingKey = ref('')
const allConfigRows = ref([])
const editValues = ref({})
const priceTierLoading = ref(false)
const priceTierRows = ref([])

const configDefs = [
  {
    group: '基础配置',
    name: '金币名称',
    key: 'coin_name',
    type: 'text',
    defaultValue: '金币',
    description: '代币名称：金币',
  },
  {
    group: '基础配置',
    name: '钻石名称',
    key: 'diamond_name',
    type: 'text',
    defaultValue: '钻石',
    description: '代币名称：钻石',
  },
  {
    group: 'IM 配置',
    name: 'IM SDK AppID',
    key: 'im_sdk_app_id',
    type: 'number',
    min: 1,
    max: 999999999999,
    defaultValue: '',
    description: '腾讯IM SDK AppID',
  },
  {
    group: 'IM 配置',
    name: 'IM SecretKey',
    key: 'im_secret_key',
    type: 'secret',
    defaultValue: '',
    description: '腾讯IM SecretKey',
  },
  {
    group: 'IM 配置',
    name: '通话 IM 留痕',
    key: 'im_call_trace_enabled',
    type: 'bool',
    defaultValue: '1',
    description: '是否启用通话 IM 留痕',
  },
  {
    group: 'IM 配置',
    name: '留痕管理员账号',
    key: 'im_admin_identifier',
    type: 'text',
    defaultValue: 'trace_bot',
    description: '腾讯 IM 通话留痕管理员账号',
  },
  {
    group: 'IM 配置',
    name: '文字聊天普通用户扣费',
    key: 'im_text_message_billing_enabled',
    type: 'bool',
    defaultValue: 'false',
    description: '是否开启 IM 普通文字聊天按条扣金币',
  },
  {
    group: 'IM 配置',
    name: '文字聊天普通用户每条扣费',
    key: 'im_text_message_price',
    type: 'number',
    unit: '金币',
    min: 0,
    max: 1000000,
    defaultValue: '0',
    description: '非认证用户给认证用户发送普通文字消息时，每条消耗的金币数',
  },
  {
    group: 'IM 配置',
    name: '文字聊天认证用户分成',
    key: 'im_text_message_certified_user_share_bps',
    type: 'percent',
    unit: '%',
    min: 0,
    max: 100,
    defaultValue: '5000',
    description: '文字聊天扣费后认证用户获得钻石的分成比例',
  },
  {
    group: 'IM 配置',
    name: '在线客服账号',
    key: 'customer_service_user_id',
    type: 'number',
    unit: '用户ID',
    min: 1,
    max: 999999999999,
    defaultValue: '',
    description: '在线客服对应的 App 用户 ID',
  },
  {
    group: 'RTC 配置',
    name: 'RTC App ID',
    key: 'rtc_app_id',
    type: 'text',
    defaultValue: '',
    description: '声网 RTC App ID',
  },
  {
    group: 'RTC 配置',
    name: 'RTC App Certificate',
    key: 'rtc_app_certificate',
    type: 'secret',
    defaultValue: '',
    description: '声网 RTC App Certificate',
  },
  {
    group: '美颜配置',
    name: '美颜 Key',
    key: 'face_beauty_key',
    type: 'secret',
    defaultValue: '',
    description: '美颜 SDK License Key',
  },
  {
    group: '计费配置',
    name: '通话免费时长',
    key: 'call_billing_free_seconds',
    type: 'number',
    unit: '秒',
    min: 0,
    max: 600,
    defaultValue: '10',
    description: '通话免费时长（秒）',
  },
  {
    group: '计费配置',
    name: '视频通话认证用户分成',
    key: 'call_certified_user_share_bps',
    type: 'percent',
    unit: '%',
    min: 0,
    max: 100,
    defaultValue: '5000',
    description: '视频通话认证用户分成比例',
  },
  {
    group: '计费配置',
    name: '礼物认证用户分成',
    key: 'gift_certified_user_share_bps',
    type: 'percent',
    unit: '%',
    min: 0,
    max: 100,
    defaultValue: '5000',
    description: '礼物认证用户分成比例',
  },
  {
    group: '互动限制',
    name: '关注仅允许异性之间',
    key: 'interaction_follow_opposite_gender_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，仅允许异性之间发起关注',
  },
  {
    group: '互动限制',
    name: '关注仅允许普通用户和认证用户之间',
    key: 'interaction_follow_certified_mix_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，仅允许普通用户与认证用户之间发起关注',
  },
  {
    group: '互动限制',
    name: '文字聊天仅允许异性之间',
    key: 'interaction_im_text_opposite_gender_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，仅允许异性之间发起文字聊天',
  },
  {
    group: '互动限制',
    name: '文字聊天仅允许普通用户和认证用户之间',
    key: 'interaction_im_text_certified_mix_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，仅允许普通用户与认证用户之间发起文字聊天',
  },
  {
    group: '互动限制',
    name: '视频通话仅允许异性之间',
    key: 'interaction_call_opposite_gender_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，仅允许异性之间发起视频通话',
  },
  {
    group: '互动限制',
    name: '视频通话仅允许普通用户和认证用户之间',
    key: 'interaction_call_certified_mix_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，仅允许普通用户与认证用户之间发起视频通话',
  },
  {
    group: '互动限制',
    name: '礼物仅允许异性之间',
    key: 'interaction_gift_opposite_gender_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，仅允许异性之间发送礼物',
  },
  {
    group: '互动限制',
    name: '礼物仅允许普通用户和认证用户之间',
    key: 'interaction_gift_certified_mix_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，仅允许普通用户与认证用户之间发送礼物',
  },
  {
    group: '用户能力限制',
    name: '只允许男性认证',
    key: 'capability_certification_male_only_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，仅允许男性用户申请真人认证',
  },
  {
    group: '用户能力限制',
    name: '只允许女性认证',
    key: 'capability_certification_female_only_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，仅允许女性用户申请真人认证',
  },
  {
    group: '用户能力限制',
    name: '只允许认证用户编辑资料',
    key: 'capability_profile_edit_certified_only_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，只有通过真人认证的用户才能编辑资料',
  },
  {
    group: '用户能力限制',
    name: '只允许认证用户发动态',
    key: 'capability_moment_publish_certified_only_enabled',
    type: 'bool',
    defaultValue: '0',
    description: '开启后，只有通过真人认证的用户才能发布动态',
  },
  {
    group: '通话保护',
    name: '拒绝后禁止呼入',
    key: 'call_reject_inbound_protect_seconds',
    type: 'number',
    unit: '秒',
    min: 0,
    max: 600,
    defaultValue: '5',
    description: '拒绝后禁止呼入保护时间（秒）',
  },
  {
    group: '通话保护',
    name: '拒绝后禁止同一用户再次呼叫',
    key: 'call_reject_pair_protect_seconds',
    type: 'number',
    unit: '秒',
    min: 0,
    max: 600,
    defaultValue: '5',
    description: '拒绝后禁止同一主叫再次呼叫保护时间（秒）',
  },
  {
    group: 'Watchdog 配置',
    name: '轮询间隔',
    key: 'call_watchdog_poll_seconds',
    type: 'number',
    unit: '秒',
    min: 1,
    max: 600,
    defaultValue: '5',
    description: 'Watchdog 轮询间隔（秒）',
  },
  {
    group: 'Watchdog 配置',
    name: '振铃超时',
    key: 'call_watchdog_ring_timeout_seconds',
    type: 'number',
    unit: '秒',
    min: 1,
    max: 600,
    defaultValue: '30',
    description: '呼叫振铃超时自动结束（秒）',
  },
  {
    group: 'Watchdog 配置',
    name: '续费宽限',
    key: 'call_watchdog_renew_grace_seconds',
    type: 'number',
    unit: '秒',
    min: 0,
    max: 5,
    defaultValue: '5',
    description: '续费宽限时长（秒）',
  },
  {
    group: 'Watchdog 配置',
    name: '离线判定阈值',
    key: 'call_presence_offline_detect_seconds',
    type: 'number',
    unit: '秒',
    min: 1,
    max: 600,
    defaultValue: '3',
    description: '在线状态离线判定阈值（秒）',
  },
  {
    group: 'Watchdog 配置',
    name: '离线结算宽限',
    key: 'call_presence_settle_grace_seconds',
    type: 'number',
    unit: '秒',
    min: 0,
    max: 30,
    defaultValue: '5',
    description: '离线结算宽限时长（秒）',
  },
]

const priceTierColumns = [
  { title: '序号', key: 'index', width: 80, align: 'center', render: (_row, index) => index + 1 },
  {
    title: '价格(金币/分钟)',
    key: 'price',
    width: 220,
    render(row) {
      if (row.editable) {
        return h(NInputNumber, {
          value: row.price,
          min: 0,
          precision: 0,
          style: { width: '100%' },
          onUpdateValue: (value) => {
            row.price = value
          },
        })
      }
      return row.price
    },
  },
  {
    title: '展示',
    key: 'display',
    width: 160,
    render(row) {
      const price = Number(row.price || 0)
      return price === 0 ? '免费' : `${price}金币/分钟`
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 220,
    align: 'center',
    render(row) {
      if (row.editable) {
        return h(NSpace, { justify: 'center' }, () => [
          h(
            NButton,
            { size: 'small', type: 'primary', onClick: () => savePriceTier(row) },
            () => '保存'
          ),
          h(NButton, { size: 'small', onClick: loadCertifiedCallPriceConfig }, () => '取消'),
        ])
      }
      return h(NSpace, { justify: 'center' }, () => [
        h(
          NButton,
          { size: 'small', disabled: row.price === 0, onClick: () => editPriceTier(row) },
          () => '编辑'
        ),
        h(
          NPopconfirm,
          { onPositiveClick: () => deletePriceTier(row) },
          {
            trigger: () =>
              h(NButton, { size: 'small', type: 'error', disabled: row.price === 0 }, () => '删除'),
            default: () => '确认删除该档位？',
          }
        ),
      ])
    },
  },
]

const tableRows = computed(() =>
  configDefs.map((def) => {
    const row = findRow(def.key)
    return {
      ...def,
      id: row?.id,
      dbValue: row?.cfg_value,
      currentValue: editValues.value[def.key] ?? def.defaultValue,
      exists: !!row,
    }
  })
)

const columns = [
  {
    title: '分类',
    key: 'group',
    width: 120,
    render(row) {
      return h(
        NTag,
        { type: groupTagType(row.group), bordered: false },
        { default: () => row.group }
      )
    },
  },
  { title: '配置名称', key: 'name', width: 190 },
  {
    title: '配置键',
    key: 'key',
    width: 260,
    ellipsis: { tooltip: true },
  },
  {
    title: '配置值',
    key: 'currentValue',
    minWidth: 260,
    render(row) {
      return renderEditor(row)
    },
  },
  {
    title: '单位/类型',
    key: 'unit',
    width: 110,
    render(row) {
      return row.unit || typeLabel(row.type)
    },
  },
  {
    title: '说明',
    key: 'description',
    minWidth: 260,
    ellipsis: { tooltip: true },
  },
  {
    title: '操作',
    key: 'actions',
    width: 120,
    fixed: 'right',
    render(row) {
      return h(
        NButton,
        {
          size: 'small',
          type: 'primary',
          loading: savingKey.value === row.key,
          disabled: loading.value,
          onClick: () => saveConfig(row),
        },
        { default: () => '保存' }
      )
    },
  },
]

onMounted(async () => {
  await Promise.all([loadAllConfigs(), loadCertifiedCallPriceConfig()])
})

async function loadAllConfigs() {
  loading.value = true
  try {
    const res = await api.getSystemConfigList({ page: 1, page_size: 500 })
    allConfigRows.value = res.data || []
    const nextValues = {}
    for (const def of configDefs) {
      nextValues[def.key] = findValue(def.key, def.defaultValue)
    }
    editValues.value = nextValues
  } catch (error) {
    allConfigRows.value = []
    message.error('加载系统配置失败')
    console.error(error)
  } finally {
    loading.value = false
  }
}

async function loadCertifiedCallPriceConfig() {
  priceTierLoading.value = true
  try {
    const res = await api.getCertifiedCallPriceConfig()
    const tiers = Array.isArray(res?.data?.tiers) ? res.data.tiers : [0, 100, 200, 300, 500]
    priceTierRows.value = normalizePriceTiers(tiers).map((price) => ({
      key: `tier-${price}`,
      price,
      editable: false,
    }))
  } catch (error) {
    priceTierRows.value = normalizePriceTiers([0, 100, 200, 300, 500]).map((price) => ({
      key: `tier-${price}`,
      price,
      editable: false,
    }))
    message.error('加载通话价格档位失败')
    console.error(error)
  } finally {
    priceTierLoading.value = false
  }
}

function findRow(cfgKey) {
  return allConfigRows.value.find((r) => r.cfg_key === cfgKey)
}

function findValue(cfgKey, fallback = '') {
  const row = findRow(cfgKey)
  if (!row) return fallback
  return (row.cfg_value ?? fallback).toString()
}

function groupTagType(group) {
  const map = {
    基础配置: 'default',
    'IM 配置': 'info',
    'RTC 配置': 'success',
    美颜配置: 'warning',
    计费配置: 'error',
    互动限制: 'warning',
    用户能力限制: 'warning',
    通话保护: 'warning',
    'Watchdog 配置': 'default',
  }
  return map[group] || 'default'
}

function typeLabel(type) {
  const map = {
    text: '文本',
    secret: '密钥',
    number: '数字',
    percent: '百分比',
    bool: '开关',
  }
  return map[type] || type
}

function normalizeBool(raw, fallback = false) {
  const value = String(raw ?? '')
    .trim()
    .toLowerCase()
  if (['1', 'true', 'yes', 'on'].includes(value)) return true
  if (['0', 'false', 'no', 'off'].includes(value)) return false
  return fallback
}

function clampNumber(raw, fallback, min, max) {
  const n = Number(raw)
  if (!Number.isFinite(n)) return fallback
  if (typeof min === 'number' && n < min) return min
  if (typeof max === 'number' && n > max) return max
  return Math.floor(n)
}

function renderEditor(row) {
  if (row.type === 'bool') {
    return h(NSwitch, {
      value: normalizeBool(row.currentValue, normalizeBool(row.defaultValue)),
      checkedValue: true,
      uncheckedValue: false,
      onUpdateValue: (value) => {
        editValues.value[row.key] = value ? '1' : '0'
      },
    })
  }
  if (row.type === 'number') {
    return h(NInputNumber, {
      value: Number(row.currentValue || row.defaultValue || 0),
      min: row.min,
      max: row.max,
      precision: 0,
      step: 1,
      placeholder: '请输入配置值',
      style: { width: '100%' },
      onUpdateValue: (value) => {
        editValues.value[row.key] = value == null ? '' : String(value)
      },
    })
  }
  if (row.type === 'percent') {
    return h(NInputNumber, {
      value: Number((Number(row.currentValue || row.defaultValue || 0) / 100).toFixed(2)),
      min: row.min,
      max: row.max,
      precision: 2,
      step: 0.01,
      placeholder: '请输入百分比',
      style: { width: '100%' },
      onUpdateValue: (value) => {
        const percent = Number(value)
        editValues.value[row.key] = Number.isFinite(percent)
          ? String(clampNumber(percent * 100, Number(row.defaultValue || 0), 0, 10000))
          : row.defaultValue
      },
    })
  }
  return h(NInput, {
    value: row.currentValue,
    type: row.type === 'secret' ? 'password' : 'text',
    showPasswordOn: row.type === 'secret' ? 'mousedown' : undefined,
    placeholder: '请输入配置值',
    onUpdateValue: (value) => {
      editValues.value[row.key] = value ?? ''
    },
  })
}

function normalizeForSave(row) {
  const raw = editValues.value[row.key] ?? row.defaultValue
  if (row.type === 'bool') {
    return normalizeBool(raw, normalizeBool(row.defaultValue)) ? '1' : '0'
  }
  if (row.type === 'number') {
    return String(clampNumber(raw, Number(row.defaultValue || 0), row.min, row.max))
  }
  if (row.type === 'percent') {
    return String(clampNumber(raw, Number(row.defaultValue || 0), 0, 10000))
  }
  return String(raw ?? '').trim()
}

async function saveConfig(row) {
  const cfgValue = normalizeForSave(row)
  savingKey.value = row.key
  try {
    if (row.id) {
      await api.updateSystemConfig({
        id: row.id,
        cfg_key: row.key,
        cfg_value: cfgValue,
        description: row.description,
      })
    } else {
      await api.createSystemConfig({
        cfg_key: row.key,
        cfg_value: cfgValue,
        description: row.description,
      })
    }
    message.success('保存成功')
    await loadAllConfigs()
  } catch (error) {
    message.error(error?.message || '保存失败')
    console.error(error)
  } finally {
    savingKey.value = ''
  }
}

function normalizePriceTiers(tiers) {
  const values = Array.from(
    new Set(tiers.map((item) => Number(item)).filter((item) => Number.isInteger(item) && item >= 0))
  ).sort((a, b) => a - b)
  if (!values.includes(0)) values.unshift(0)
  return values
}

function hasPaidPriceTier(tiers) {
  return tiers.some((price) => Number(price) > 0)
}

function addPriceTier() {
  priceTierRows.value.push({
    key: `tier-new-${Date.now()}`,
    price: 100,
    editable: true,
  })
}

function editPriceTier(row) {
  if (row.price === 0) return
  row.editable = true
}

async function savePriceTier(row) {
  const price = Number(row.price)
  if (!Number.isInteger(price) || price < 0) {
    message.warning('价格必须是非负整数')
    return
  }
  row.price = price
  row.editable = false
  await saveCertifiedCallPriceConfig()
}

async function deletePriceTier(row) {
  if (row.price === 0) {
    message.warning('免费档不能删除')
    return
  }
  const nextRows = priceTierRows.value.filter((item) => item.key !== row.key)
  if (!hasPaidPriceTier(nextRows.map((item) => item.price))) {
    message.warning('请至少保留一个收费档位')
    return
  }
  priceTierRows.value = nextRows
  await saveCertifiedCallPriceConfig()
}

async function saveCertifiedCallPriceConfig() {
  priceTierLoading.value = true
  try {
    const tiers = normalizePriceTiers(priceTierRows.value.map((item) => item.price))
    if (!hasPaidPriceTier(tiers)) {
      message.warning('请至少保留一个收费档位')
      return
    }
    await api.updateCertifiedCallPriceConfig({ tiers })
    message.success('保存成功')
    priceTierRows.value = tiers.map((price) => ({
      key: `tier-${price}`,
      price,
      editable: false,
    }))
  } catch (error) {
    message.error(error?.message || '保存失败')
    console.error(error)
    await loadCertifiedCallPriceConfig()
  } finally {
    priceTierLoading.value = false
  }
}
</script>

<template>
  <CommonPage title="系统配置">
    <NSpace vertical :size="16" class="mb-20">
      <NSpace justify="end">
        <NButton :loading="loading" @click="loadAllConfigs">刷新</NButton>
      </NSpace>
      <NDataTable
        :columns="columns"
        :data="tableRows"
        :loading="loading"
        :pagination="false"
        :bordered="true"
        :single-line="false"
        :scroll-x="1320"
      />
      <NSpace justify="space-between" align="center" class="mt-20">
        <div class="section-title">认证用户通话价格档位</div>
        <NButton type="primary" @click="addPriceTier">新增档位</NButton>
      </NSpace>
      <NDataTable
        :columns="priceTierColumns"
        :data="priceTierRows"
        :loading="priceTierLoading"
        :pagination="false"
        :bordered="true"
        :single-line="false"
      />
    </NSpace>
  </CommonPage>
</template>

<style scoped>
.section-title {
  font-size: 16px;
  font-weight: 600;
}
</style>
