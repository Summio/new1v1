<script setup>
import { computed, onMounted, ref } from 'vue'
import { NButton, NCard, NForm, NFormItem, NInput, NInputNumber, NSpace, NSwitch } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import api from '@/api'

defineOptions({ name: '系统配置' })

const allConfigRows = ref([])

const tokenLoading = ref(false)
const imLoading = ref(false)
const rtcLoading = ref(false)
const faceBeautyLoading = ref(false)
const billingLoading = ref(false)
const protectLoading = ref(false)
const watchdogLoading = ref(false)

const tokenForm = ref({
  coin_name: '金币',
  diamond_name: '钻石',
})

const imForm = ref({
  im_sdk_app_id: null,
  im_secret_key: '',
  im_call_trace_enabled: true,
  im_admin_identifier: 'trace_bot',
})

const rtcForm = ref({
  rtc_app_id: '',
  rtc_app_certificate: '',
})

const faceBeautyForm = ref({
  face_beauty_key: '',
})

const billingForm = ref({
  call_billing_free_seconds: 10,
  call_anchor_share_bps: 5000,
})

const anchorSharePercent = computed({
  get() {
    return Number((Number(billingForm.value.call_anchor_share_bps || 0) / 100).toFixed(2))
  },
  set(value) {
    const percent = Number(value)
    if (!Number.isFinite(percent)) {
      billingForm.value.call_anchor_share_bps = 5000
      return
    }
    billingForm.value.call_anchor_share_bps = normalizeSeconds(percent * 100, 5000, 0, 10000)
  },
})

const protectForm = ref({
  reject_inbound_protect_seconds: 5,
  reject_pair_protect_seconds: 5,
})

const watchdogForm = ref({
  call_watchdog_poll_seconds: 5,
  call_watchdog_ring_timeout_seconds: 30,
  call_watchdog_renew_grace_seconds: 5,
  call_presence_offline_detect_seconds: 3,
  call_presence_settle_grace_seconds: 5,
})

onMounted(async () => {
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
    imForm.value.im_call_trace_enabled = normalizeBool(
      findValue('im_call_trace_enabled', '1'),
      true
    )
    imForm.value.im_admin_identifier = findValue('im_admin_identifier', 'trace_bot')

    rtcForm.value.rtc_app_id = findValue('rtc_app_id', '')
    rtcForm.value.rtc_app_certificate = findValue('rtc_app_certificate', '')

    faceBeautyForm.value.face_beauty_key = findValue('face_beauty_key', '')

    billingForm.value.call_billing_free_seconds = normalizeSeconds(
      findValue('call_billing_free_seconds', '10'),
      10,
      0,
      600
    )
    billingForm.value.call_anchor_share_bps = normalizeSeconds(
      findValue('call_anchor_share_bps', '5000'),
      5000,
      0,
      10000
    )

    protectForm.value.reject_inbound_protect_seconds = normalizeSeconds(
      findValue('call_reject_inbound_protect_seconds', '5'),
      5,
      0,
      600
    )
    protectForm.value.reject_pair_protect_seconds = normalizeSeconds(
      findValue('call_reject_pair_protect_seconds', '5'),
      5,
      0,
      600
    )

    watchdogForm.value.call_watchdog_poll_seconds = normalizeSeconds(
      findValue('call_watchdog_poll_seconds', '5'),
      5,
      1,
      600
    )
    watchdogForm.value.call_watchdog_ring_timeout_seconds = normalizeSeconds(
      findValue('call_watchdog_ring_timeout_seconds', '30'),
      30,
      1,
      600
    )
    watchdogForm.value.call_watchdog_renew_grace_seconds = normalizeSeconds(
      findValue('call_watchdog_renew_grace_seconds', '5'),
      5,
      0,
      5
    )
    watchdogForm.value.call_presence_offline_detect_seconds = normalizeSeconds(
      findValue('call_presence_offline_detect_seconds', '3'),
      3,
      1,
      600
    )
    watchdogForm.value.call_presence_settle_grace_seconds = normalizeSeconds(
      findValue('call_presence_settle_grace_seconds', '5'),
      5,
      0,
      30
    )
  } catch (_) {
    allConfigRows.value = []
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

function normalizeSeconds(raw, fallback, min = 0, max = 600) {
  const n = Number(raw)
  if (!Number.isFinite(n)) return fallback
  if (n < min) return min
  if (n > max) return max
  return Math.floor(n)
}

function normalizeNullablePositiveInt(raw) {
  const n = Number(raw)
  if (!Number.isFinite(n) || n <= 0) return null
  return Math.floor(n)
}

function normalizeBool(raw, fallback = false) {
  const value = String(raw ?? '')
    .trim()
    .toLowerCase()
  if (['1', 'true', 'yes', 'on'].includes(value)) return true
  if (['0', 'false', 'no', 'off'].includes(value)) return false
  return fallback
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
    await upsertConfig(
      'diamond_name',
      tokenForm.value.diamond_name.trim() || '钻石',
      '代币名称：钻石'
    )
    await loadAllConfigs()
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
    await upsertConfig(
      'im_call_trace_enabled',
      imForm.value.im_call_trace_enabled ? '1' : '0',
      '是否启用通话 IM 留痕'
    )
    await upsertConfig(
      'im_admin_identifier',
      imForm.value.im_admin_identifier.trim() || 'trace_bot',
      '腾讯 IM 通话留痕管理员账号'
    )
    await loadAllConfigs()
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
    $message.success('RTC 配置已保存')
  } catch (_) {
    $message.error('保存失败，请稍后重试')
  } finally {
    rtcLoading.value = false
  }
}

async function saveFaceBeautyConfigs() {
  faceBeautyLoading.value = true
  try {
    await upsertConfig(
      'face_beauty_key',
      faceBeautyForm.value.face_beauty_key.trim(),
      '美颜 SDK License Key'
    )
    await loadAllConfigs()
    $message.success('美颜配置已保存')
  } catch (_) {
    $message.error('保存失败，请稍后重试')
  } finally {
    faceBeautyLoading.value = false
  }
}

async function saveBillingConfigs() {
  billingLoading.value = true
  try {
    const freeSeconds = normalizeSeconds(billingForm.value.call_billing_free_seconds, 10, 0, 600)
    const anchorShareBps = normalizeSeconds(billingForm.value.call_anchor_share_bps, 5000, 0, 10000)
    await upsertConfig('call_billing_free_seconds', String(freeSeconds), '通话免费时长（秒）')
    await upsertConfig(
      'call_anchor_share_bps',
      String(anchorShareBps),
      '视频通话主播分成比例（万分比）'
    )
    await loadAllConfigs()
    $message.success('计费配置已保存')
  } catch (_) {
    $message.error('保存失败，请稍后重试')
  } finally {
    billingLoading.value = false
  }
}

async function saveProtectConfigs() {
  protectLoading.value = true
  try {
    const inbound = normalizeSeconds(protectForm.value.reject_inbound_protect_seconds, 5, 0, 600)
    const pair = normalizeSeconds(protectForm.value.reject_pair_protect_seconds, 5, 0, 600)

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
    $message.success('通话保护配置已保存')
  } catch (_) {
    $message.error('保存失败，请稍后重试')
  } finally {
    protectLoading.value = false
  }
}

async function saveWatchdogConfigs() {
  watchdogLoading.value = true
  try {
    const pollSeconds = normalizeSeconds(watchdogForm.value.call_watchdog_poll_seconds, 5, 1, 600)
    const ringTimeout = normalizeSeconds(
      watchdogForm.value.call_watchdog_ring_timeout_seconds,
      30,
      1,
      600
    )
    const renewGrace = normalizeSeconds(
      watchdogForm.value.call_watchdog_renew_grace_seconds,
      5,
      0,
      5
    )
    const offlineDetect = normalizeSeconds(
      watchdogForm.value.call_presence_offline_detect_seconds,
      3,
      1,
      600
    )
    const settleGrace = normalizeSeconds(
      watchdogForm.value.call_presence_settle_grace_seconds,
      5,
      0,
      30
    )

    await upsertConfig('call_watchdog_poll_seconds', String(pollSeconds), 'Watchdog 轮询间隔（秒）')
    await upsertConfig(
      'call_watchdog_ring_timeout_seconds',
      String(ringTimeout),
      '呼叫振铃超时自动结束（秒）'
    )
    await upsertConfig(
      'call_watchdog_renew_grace_seconds',
      String(renewGrace),
      '续费宽限时长（秒）'
    )
    await upsertConfig(
      'call_presence_offline_detect_seconds',
      String(offlineDetect),
      '在线状态离线判定阈值（秒）'
    )
    await upsertConfig(
      'call_presence_settle_grace_seconds',
      String(settleGrace),
      '离线结算宽限时长（秒）'
    )

    await loadAllConfigs()
    $message.success('Watchdog 配置已保存')
  } catch (_) {
    $message.error('保存失败，请稍后重试')
  } finally {
    watchdogLoading.value = false
  }
}
</script>

<template>
  <CommonPage title="系统配置">
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
        <NButton type="primary" :loading="tokenLoading" @click="saveTokenConfigs"
          >保存基础配置</NButton
        >
      </NCard>

      <NCard title="IM 配置（腾讯云）">
        <NForm label-placement="left" label-align="left" :label-width="180" :model="imForm">
          <NFormItem label="IM SDK AppID im_sdk_app_id">
            <NInputNumber
              v-model:value="imForm.im_sdk_app_id"
              :min="1"
              placeholder="请输入数字 AppID"
            />
          </NFormItem>
          <NFormItem label="IM SecretKey im_secret_key">
            <NInput
              v-model:value="imForm.im_secret_key"
              type="password"
              show-password-on="mousedown"
              placeholder="请输入 IM SecretKey"
            />
          </NFormItem>
          <NFormItem label="通话留痕 im_call_trace_enabled">
            <NSwitch v-model:value="imForm.im_call_trace_enabled" />
          </NFormItem>
          <NFormItem label="留痕管理员 im_admin_identifier">
            <NInput v-model:value="imForm.im_admin_identifier" placeholder="例如：trace_bot" />
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
        <NButton type="primary" :loading="rtcLoading" @click="saveRtcConfigs"
          >保存 RTC 配置</NButton
        >
      </NCard>

      <NCard title="美颜配置">
        <NForm label-placement="left" label-align="left" :label-width="200" :model="faceBeautyForm">
          <NFormItem label="美颜 Key face_beauty_key">
            <NInput
              v-model:value="faceBeautyForm.face_beauty_key"
              type="password"
              show-password-on="mousedown"
              placeholder="请输入美颜 SDK Key"
            />
          </NFormItem>
        </NForm>
        <NButton type="primary" :loading="faceBeautyLoading" @click="saveFaceBeautyConfigs">
          保存美颜配置
        </NButton>
      </NCard>

      <NCard title="通话计费配置">
        <NForm label-placement="left" label-align="left" :label-width="260" :model="billingForm">
          <NFormItem label="通话免费时长（秒） call_billing_free_seconds">
            <NInputNumber
              v-model:value="billingForm.call_billing_free_seconds"
              :min="0"
              :max="600"
              placeholder="例如 10"
            />
          </NFormItem>
          <NFormItem label="视频通话主播分成比例（%） call_anchor_share_bps">
            <NInputNumber
              v-model:value="anchorSharePercent"
              :min="0"
              :max="100"
              :step="0.01"
              placeholder="例如 50"
            />
          </NFormItem>
        </NForm>
        <NButton type="primary" :loading="billingLoading" @click="saveBillingConfigs"
          >保存计费配置</NButton
        >
      </NCard>

      <NCard title="通话保护配置">
        <NForm label-placement="left" label-align="left" :label-width="260" :model="protectForm">
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

      <NCard title="Watchdog 配置">
        <NForm label-placement="left" label-align="left" :label-width="300" :model="watchdogForm">
          <NFormItem label="轮询间隔（秒） call_watchdog_poll_seconds">
            <NInputNumber
              v-model:value="watchdogForm.call_watchdog_poll_seconds"
              :min="1"
              :max="600"
              placeholder="例如 5"
            />
          </NFormItem>
          <NFormItem label="振铃超时（秒） call_watchdog_ring_timeout_seconds">
            <NInputNumber
              v-model:value="watchdogForm.call_watchdog_ring_timeout_seconds"
              :min="1"
              :max="600"
              placeholder="例如 30"
            />
          </NFormItem>
          <NFormItem label="续费宽限（秒） call_watchdog_renew_grace_seconds">
            <NInputNumber
              v-model:value="watchdogForm.call_watchdog_renew_grace_seconds"
              :min="0"
              :max="5"
              placeholder="例如 5"
            />
          </NFormItem>
          <NFormItem label="离线判定阈值（秒） call_presence_offline_detect_seconds">
            <NInputNumber
              v-model:value="watchdogForm.call_presence_offline_detect_seconds"
              :min="1"
              :max="600"
              placeholder="例如 3"
            />
          </NFormItem>
          <NFormItem label="离线结算宽限（秒） call_presence_settle_grace_seconds">
            <NInputNumber
              v-model:value="watchdogForm.call_presence_settle_grace_seconds"
              :min="0"
              :max="30"
              placeholder="例如 5"
            />
          </NFormItem>
        </NForm>
        <NButton type="primary" :loading="watchdogLoading" @click="saveWatchdogConfigs">
          保存 Watchdog 配置
        </NButton>
      </NCard>
    </NSpace>
  </CommonPage>
</template>
