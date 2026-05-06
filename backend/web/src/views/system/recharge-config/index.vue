<script setup>
import { onMounted, ref } from 'vue'
import { NButton, NCard, NForm, NFormItem, NInput, NInputNumber, NSpace, useMessage } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import api from '@/api'

defineOptions({ name: '充值配置' })

const message = useMessage()
const loading = ref(false)
const saving = ref(false)

const formRef = ref(null)
const packages = ref([])

onMounted(async () => {
  await loadConfig()
})

async function loadConfig() {
  loading.value = true
  try {
    const res = await api.getRechargeConfig()
    if (res.data && Array.isArray(res.data.packages)) {
      packages.value = res.data.packages.map((pkg) => ({
        amount: (pkg.amount / 100).toFixed(2),
        coins: pkg.coins,
        label: pkg.label || '',
        tag: pkg.tag || '',
      }))
    }
    else {
      packages.value = []
    }
  }
  catch (error) {
    message.error('加载充值配置失败')
    console.error(error)
  }
  finally {
    loading.value = false
  }
}

function addPackage() {
  packages.value.push({
    amount: '6.00',
    coins: 600,
    label: '',
    tag: '',
  })
}

function removePackage(index) {
  if (packages.value.length <= 1) {
    message.warning('至少保留一个充值套餐')
    return
  }
  packages.value.splice(index, 1)
}

function moveUp(index) {
  if (index === 0) return
  const temp = packages.value[index]
  packages.value[index] = packages.value[index - 1]
  packages.value[index - 1] = temp
}

function moveDown(index) {
  if (index === packages.value.length - 1) return
  const temp = packages.value[index]
  packages.value[index] = packages.value[index + 1]
  packages.value[index + 1] = temp
}

async function handleSave() {
  try {
    await formRef.value?.validate()
  }
  catch (error) {
    message.error('请检查表单填写是否正确')
    return
  }

  // 验证套餐数据
  for (let i = 0; i < packages.value.length; i++) {
    const pkg = packages.value[i]
    const amountNum = Number(pkg.amount)
    const coinsNum = Number(pkg.coins)

    if (!amountNum || amountNum <= 0) {
      message.error(`第 ${i + 1} 个套餐的金额必须大于 0`)
      return
    }
    if (!coinsNum || coinsNum <= 0) {
      message.error(`第 ${i + 1} 个套餐的金币数必须大于 0`)
      return
    }
    if (!pkg.label || pkg.label.trim() === '') {
      message.error(`第 ${i + 1} 个套餐的标签不能为空`)
      return
    }
  }

  saving.value = true
  try {
    await api.updateRechargeConfig({
      packages: packages.value.map((pkg) => ({
        amount: Math.round(Number(pkg.amount) * 100),
        coins: Number(pkg.coins),
        label: pkg.label.trim(),
        tag: pkg.tag ? pkg.tag.trim() : '',
      })),
    })
    message.success('保存成功，配置将在60秒内生效')
    await loadConfig()
  }
  catch (error) {
    message.error(error?.message || '保存失败')
    console.error(error)
  }
  finally {
    saving.value = false
  }
}

function handleReset() {
  loadConfig()
}

const rules = {
  amount: [
    { required: true, message: '请输入金额', trigger: ['blur', 'change'] },
    {
      validator: (rule, value) => {
        const num = Number(value)
        if (isNaN(num) || num <= 0) {
          return new Error('金额必须大于 0')
        }
        if (num > 100000) {
          return new Error('金额不能超过 100000 元')
        }
        return true
      },
      trigger: ['blur', 'change'],
    },
  ],
  coins: [
    { required: true, message: '请输入金币数', trigger: ['blur', 'change'] },
    {
      validator: (rule, value) => {
        const num = Number(value)
        if (isNaN(num) || num <= 0 || !Number.isInteger(num)) {
          return new Error('金币数必须是大于 0 的整数')
        }
        return true
      },
      trigger: ['blur', 'change'],
    },
  ],
  label: [
    { required: true, message: '请输入标签', trigger: ['blur', 'change'] },
    {
      validator: (rule, value) => {
        if (!value || value.trim() === '') {
          return new Error('标签不能为空')
        }
        if (value.length > 20) {
          return new Error('标签最多20个字符')
        }
        return true
      },
      trigger: ['blur', 'change'],
    },
  ],
  tag: [
    {
      validator: (rule, value) => {
        if (value && value.length > 10) {
          return new Error('角标最多10个字符')
        }
        return true
      },
      trigger: ['blur', 'change'],
    },
  ],
}
</script>

<template>
  <CommonPage show-footer>
    <NCard title="充值套餐配置" :bordered="false" :segmented="{ content: true }">
      <template #header-extra>
        <NSpace>
          <NButton type="primary" @click="addPackage">
            添加套餐
          </NButton>
          <NButton @click="handleReset" :loading="loading">
            重置
          </NButton>
          <NButton type="success" @click="handleSave" :loading="saving">
            保存配置
          </NButton>
        </NSpace>
      </template>

      <NForm ref="formRef" :model="{ packages }" label-placement="left" label-width="120">
        <div v-if="packages.length === 0" style="text-align: center; padding: 40px 0; color: #999">
          暂无充值套餐，请点击"添加套餐"按钮添加
        </div>

        <div v-for="(pkg, index) in packages" :key="index" class="package-item">
          <div class="package-header">
            <span class="package-title">套餐 {{ index + 1 }}</span>
            <NSpace>
              <NButton
                size="small"
                :disabled="index === 0"
                @click="moveUp(index)"
              >
                上移
              </NButton>
              <NButton
                size="small"
                :disabled="index === packages.length - 1"
                @click="moveDown(index)"
              >
                下移
              </NButton>
              <NButton
                size="small"
                type="error"
                secondary
                @click="removePackage(index)"
              >
                删除
              </NButton>
            </NSpace>
          </div>

          <NFormItem
            label="金额(元)"
            :path="`packages[${index}].amount`"
            :rule="rules.amount"
          >
            <NInputNumber
              v-model:value="pkg.amount"
              :min="0.01"
              :max="100000"
              :step="1"
              :precision="2"
              placeholder="请输入金额(单位:元)"
              style="width: 100%"
            >
              <template #suffix>
                元
              </template>
            </NInputNumber>
          </NFormItem>

          <NFormItem
            label="金币数"
            :path="`packages[${index}].coins`"
            :rule="rules.coins"
          >
            <NInputNumber
              v-model:value="pkg.coins"
              :min="1"
              :step="10"
              :precision="0"
              placeholder="请输入金币数"
              style="width: 100%"
            />
          </NFormItem>

          <NFormItem
            label="标签文本"
            :path="`packages[${index}].label`"
            :rule="rules.label"
          >
            <NInput
              v-model:value="pkg.label"
              placeholder="例如: 6元、30元等(必填)"
              maxlength="20"
              show-count
            />
          </NFormItem>

          <NFormItem
            label="角标文本"
            :path="`packages[${index}].tag`"
            :rule="rules.tag"
          >
            <NInput
              v-model:value="pkg.tag"
              placeholder="例如: 尝鲜、推荐、特惠等(可选)"
              maxlength="10"
              show-count
            />
          </NFormItem>
        </div>
      </NForm>
    </NCard>
  </CommonPage>
</template>

<style scoped>
.package-item {
  padding: 20px;
  margin-bottom: 16px;
  border: 1px solid #e0e0e6;
  border-radius: 8px;
  background-color: #fafafa;
}

.package-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid #e0e0e6;
}

.package-title {
  font-size: 16px;
  font-weight: 600;
  color: #333;
}

.action-buttons {
  display: flex;
  gap: 8px;
  justify-content: center;
}
</style>
