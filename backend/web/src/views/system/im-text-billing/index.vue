<script setup>
import { computed, onMounted, ref } from 'vue'
import {
  NButton,
  NCard,
  NForm,
  NFormItem,
  NInputNumber,
  NSpace,
  NSwitch,
  useMessage,
} from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import api from '@/api'

defineOptions({ name: '文字聊天计费' })

const message = useMessage()
const loading = ref(false)
const form = ref({
  enabled: false,
  price: 0,
  anchor_share_bps: 5000,
})

const sharePercent = computed({
  get() {
    return Number((Number(form.value.anchor_share_bps || 0) / 100).toFixed(2))
  },
  set(value) {
    const percent = Number(value)
    form.value.anchor_share_bps = Number.isFinite(percent)
      ? Math.min(10000, Math.max(0, Math.round(percent * 100)))
      : 5000
  },
})

onMounted(async () => {
  await loadConfig()
})

async function loadConfig() {
  loading.value = true
  try {
    const res = await api.getIMTextBillingConfig()
    const data = res.data || {}
    form.value.enabled = data.enabled === true
    form.value.price = Number(data.price || 0)
    form.value.anchor_share_bps = Number(data.anchor_share_bps || 5000)
  } catch (error) {
    message.error('加载文字聊天计费配置失败')
    console.error(error)
  } finally {
    loading.value = false
  }
}

async function saveConfig() {
  const price = Number(form.value.price || 0)
  const anchorShareBps = Number(form.value.anchor_share_bps || 0)
  if (form.value.enabled && price <= 0) {
    message.error('开启扣费时每条扣费必须大于 0')
    return
  }
  if (anchorShareBps < 0 || anchorShareBps > 10000) {
    message.error('主播分成比例必须在 0% 到 100% 之间')
    return
  }

  loading.value = true
  try {
    await api.updateIMTextBillingConfig({
      enabled: form.value.enabled,
      price,
      anchor_share_bps: anchorShareBps,
    })
    message.success('保存成功')
    await loadConfig()
  } catch (error) {
    message.error(error?.message || '保存失败')
    console.error(error)
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <CommonPage show-footer title="文字聊天计费">
    <NCard :bordered="false" size="small">
      <NForm label-placement="left" label-width="150" style="max-width: 680px">
        <NFormItem label="开启文字聊天扣费">
          <NSwitch v-model:value="form.enabled" :disabled="loading" />
        </NFormItem>
        <NFormItem label="每条扣费金币数">
          <NInputNumber
            v-model:value="form.price"
            :min="0"
            :max="1000000"
            :precision="0"
            :step="1"
            :disabled="loading"
            style="width: 220px"
          />
        </NFormItem>
        <NFormItem label="主播分成比例">
          <NInputNumber
            v-model:value="sharePercent"
            :min="0"
            :max="100"
            :precision="2"
            :step="1"
            :disabled="loading"
            style="width: 220px"
          >
            <template #suffix> % </template>
          </NInputNumber>
        </NFormItem>
        <NFormItem>
          <NSpace>
            <NButton type="primary" :loading="loading" @click="saveConfig"> 保存 </NButton>
            <NButton :disabled="loading" @click="loadConfig"> 刷新 </NButton>
          </NSpace>
        </NFormItem>
      </NForm>
    </NCard>
  </CommonPage>
</template>
