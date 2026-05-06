<script setup>
import { h, onMounted, ref } from 'vue'
import { NButton, NInput, NInputNumber, NPopconfirm, NSpace, NTag, useMessage } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'

defineOptions({ name: '充值配置' })

const message = useMessage()
const $table = ref(null)
const loading = ref(false)
const packages = ref([])
const editingKey = ref('')

onMounted(async () => {
  await loadConfig()
})

async function loadConfig() {
  loading.value = true
  try {
    const res = await api.getRechargeConfig()
    if (res.data && Array.isArray(res.data.packages)) {
      packages.value = res.data.packages.map((pkg, index) => ({
        key: `pkg-${index}`,
        amount: (pkg.amount / 100).toFixed(2),
        coins: pkg.coins,
        label: pkg.label || '',
        tag: pkg.tag || '',
        editable: false,
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
  const newKey = `pkg-${Date.now()}`
  packages.value.push({
    key: newKey,
    amount: '6.00',
    coins: 600,
    label: '',
    tag: '',
    editable: true,
  })
  editingKey.value = newKey
}

function handleEdit(row) {
  editingKey.value = row.key
  row.editable = true
}

function handleCancel(row) {
  if (!row.amount || !row.coins || !row.label) {
    // 新增的空行，直接删除
    const index = packages.value.findIndex(p => p.key === row.key)
    if (index > -1) {
      packages.value.splice(index, 1)
    }
  }
  else {
    row.editable = false
  }
  editingKey.value = ''
}

function handleDelete(row) {
  const index = packages.value.findIndex(p => p.key === row.key)
  if (index > -1) {
    packages.value.splice(index, 1)
  }
}

function moveUp(row) {
  const index = packages.value.findIndex(p => p.key === row.key)
  if (index > 0) {
    const temp = packages.value[index]
    packages.value[index] = packages.value[index - 1]
    packages.value[index - 1] = temp
  }
}

function moveDown(row) {
  const index = packages.value.findIndex(p => p.key === row.key)
  if (index < packages.value.length - 1) {
    const temp = packages.value[index]
    packages.value[index] = packages.value[index + 1]
    packages.value[index + 1] = temp
  }
}

async function handleSave() {
  // 验证数据
  for (let i = 0; i < packages.value.length; i++) {
    const pkg = packages.value[i]
    const amountNum = Number(pkg.amount)
    const coinsNum = Number(pkg.coins)

    if (!amountNum || amountNum <= 0) {
      message.error(`第 ${i + 1} 个套餐的金额必须大于 0`)
      return
    }
    if (!coinsNum || coinsNum <= 0 || !Number.isInteger(coinsNum)) {
      message.error(`第 ${i + 1} 个套餐的金币数必须是大于 0 的整数`)
      return
    }
    if (!pkg.label || pkg.label.trim() === '') {
      message.error(`第 ${i + 1} 个套餐的标签不能为空`)
      return
    }
    if (pkg.label.length > 20) {
      message.error(`第 ${i + 1} 个套餐的标签最多20个字符`)
      return
    }
    if (pkg.tag && pkg.tag.length > 10) {
      message.error(`第 ${i + 1} 个套餐的角标最多10个字符`)
      return
    }
  }

  loading.value = true
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
    editingKey.value = ''
    await loadConfig()
  }
  catch (error) {
    message.error(error?.message || '保存失败')
    console.error(error)
  }
  finally {
    loading.value = false
  }
}

const columns = [
  {
    title: '序号',
    key: 'index',
    width: 80,
    align: 'center',
    render: (row, index) => index + 1,
  },
  {
    title: '金额(元)',
    key: 'amount',
    width: 150,
    render(row) {
      if (row.editable) {
        return h(NInputNumber, {
          value: row.amount,
          min: 0.01,
          max: 100000,
          step: 1,
          precision: 2,
          placeholder: '请输入金额',
          style: { width: '100%' },
          onUpdateValue: (val) => {
            row.amount = val
          },
        })
      }
      return `¥${row.amount}`
    },
  },
  {
    title: '金币数',
    key: 'coins',
    width: 150,
    render(row) {
      if (row.editable) {
        return h(NInputNumber, {
          value: row.coins,
          min: 1,
          step: 10,
          precision: 0,
          placeholder: '请输入金币数',
          style: { width: '100%' },
          onUpdateValue: (val) => {
            row.coins = val
          },
        })
      }
      return row.coins
    },
  },
  {
    title: '标签',
    key: 'label',
    width: 200,
    render(row) {
      if (row.editable) {
        return h(NInput, {
          value: row.label,
          placeholder: '例如: 6元、30元',
          maxlength: 20,
          showCount: true,
          onUpdateValue: (val) => {
            row.label = val
          },
        })
      }
      return row.label || '-'
    },
  },
  {
    title: '角标',
    key: 'tag',
    width: 150,
    render(row) {
      if (row.editable) {
        return h(NInput, {
          value: row.tag,
          placeholder: '例如: 推荐',
          maxlength: 10,
          showCount: true,
          onUpdateValue: (val) => {
            row.tag = val
          },
        })
      }
      return row.tag ? h(NTag, { type: 'success', size: 'small' }, { default: () => row.tag }) : '-'
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 280,
    align: 'center',
    fixed: 'right',
    render(row, index) {
      if (row.editable) {
        return h(NSpace, { justify: 'center' }, {
          default: () => [
            h(NButton, {
              size: 'small',
              type: 'primary',
              onClick: () => {
                row.editable = false
                editingKey.value = ''
              },
            }, { default: () => '完成' }),
            h(NButton, {
              size: 'small',
              onClick: () => handleCancel(row),
            }, { default: () => '取消' }),
          ],
        })
      }

      return h(NSpace, { justify: 'center' }, {
        default: () => [
          h(NButton, {
            size: 'small',
            type: 'primary',
            secondary: true,
            disabled: editingKey.value !== '',
            onClick: () => handleEdit(row),
          }, { default: () => '编辑' }),
          h(NButton, {
            size: 'small',
            disabled: editingKey.value !== '' || index === 0,
            onClick: () => moveUp(row),
          }, { default: () => '上移' }),
          h(NButton, {
            size: 'small',
            disabled: editingKey.value !== '' || index === packages.value.length - 1,
            onClick: () => moveDown(row),
          }, { default: () => '下移' }),
          h(NPopconfirm, {
            onPositiveClick: () => handleDelete(row),
          }, {
            trigger: () => h(NButton, {
              size: 'small',
              type: 'error',
              secondary: true,
              disabled: editingKey.value !== '',
            }, { default: () => '删除' }),
            default: () => '确认删除该套餐？',
          }),
        ],
      })
    },
  },
]

</script>

<template>
  <CommonPage show-footer title="充值配置">
    <template #action>
      <NSpace>
        <NButton type="primary" :disabled="editingKey !== ''" @click="addPackage">
          添加套餐
        </NButton>
        <NButton type="success" :loading="loading" :disabled="editingKey !== ''" @click="handleSave">
          保存配置
        </NButton>
      </NSpace>
    </template>

    <CrudTable
      ref="$table"
      :columns="columns"
      :data="packages"
      :loading="loading"
      :pagination="false"
    />
  </CommonPage>
</template>

<style scoped>
</style>
