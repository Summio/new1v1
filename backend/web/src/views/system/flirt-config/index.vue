<script setup>
import { onMounted, ref } from 'vue'
import { NAlert, NButton, NCard, NSpace, NSwitch, useMessage } from 'naive-ui'

import api from '@/api'
import CommonPage from '@/components/page/CommonPage.vue'

defineOptions({ name: '搭讪配置' })

const message = useMessage()
const loading = ref(false)
const form = ref({
  filter_same_gender_enabled: true,
  filter_certified_user_enabled: true,
})

onMounted(async () => {
  await loadConfig()
})

async function loadConfig() {
  loading.value = true
  try {
    const res = await api.getFlirtConfig()
    form.value = {
      filter_same_gender_enabled: res.data?.filter_same_gender_enabled !== false,
      filter_certified_user_enabled: res.data?.filter_certified_user_enabled !== false,
    }
  } catch (error) {
    message.error('加载搭讪配置失败')
    console.error(error)
  } finally {
    loading.value = false
  }
}

async function saveConfig() {
  loading.value = true
  try {
    await api.updateFlirtConfig(form.value)
    message.success('保存成功')
  } catch (error) {
    message.error(error?.message || '保存失败')
    console.error(error)
    await loadConfig()
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <CommonPage show-footer title="搭讪配置">
    <NCard :bordered="false">
      <NSpace vertical size="large">
        <NAlert type="info" :show-icon="false">
          调整首页搭讪页的用户展示范围，两个开关默认均开启。
        </NAlert>

        <div class="config-row">
          <div>
            <div class="config-title">过滤同性别</div>
            <div class="config-desc">开启后仅展示异性用户</div>
          </div>
          <NSwitch
            v-model:value="form.filter_same_gender_enabled"
            :loading="loading"
          />
        </div>

        <div class="config-row">
          <div>
            <div class="config-title">过滤认证用户</div>
            <div class="config-desc">开启后隐藏真人认证用户，仅展示普通用户</div>
          </div>
          <NSwitch
            v-model:value="form.filter_certified_user_enabled"
            :loading="loading"
          />
        </div>

        <NSpace justify="end">
          <NButton :loading="loading" @click="loadConfig">重置</NButton>
          <NButton type="primary" :loading="loading" @click="saveConfig">
            保存配置
          </NButton>
        </NSpace>
      </NSpace>
    </NCard>
  </CommonPage>
</template>

<style scoped>
.config-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  padding: 16px 0;
  border-bottom: 1px solid var(--n-border-color);
}

.config-row:last-of-type {
  border-bottom: 0;
}

.config-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--n-text-color);
}

.config-desc {
  margin-top: 6px;
  font-size: 13px;
  color: var(--n-text-color-3);
}
</style>
