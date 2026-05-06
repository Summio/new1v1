<script setup>
import { h, onMounted, ref } from 'vue'
import { NButton, NColorPicker, NDataTable, NInput, NInputNumber, NPopconfirm, NSpace, NTag, useMessage } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
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
        tag: pkg.tag || '',
        tag_color: pkg.tag_color || '#FF5722',
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
    tag: '',
    tag_color: '#FF5722',
    editable: true,
  })
  editingKey.value = newKey
}

function handleEdit(row) {
  editingKey.value = row.key
  row.editable = true
}

async function handleSaveRow(row) {
  // 验证当前行
  const amountNum = Number(row.amount)
  const coinsNum = Number(row.coins)

  if (!amountNum || amountNum <= 0) {
    message.error('金额必须大于 0')
    return
  }
  if (!coinsNum || coinsNum <= 0 || !Number.isInteger(coinsNum)) {
    message.error('金币数必须是大于 0 的整数')
    return
  }
  if (row.tag && row.tag.length > 10) {
    message.error('角标最多10个字符')
    return
  }

  row.editable = false
  editingKey.value = ''

  // 自动保存到后端
  await saveToBackend()
}

function handleCancel(row) {
  if (!row.amount || !row.coins) {
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

async function handleDelete(row) {
  const index = packages.value.findIndex(p => p.key === row.key)
  if (index > -1) {
    packages.value.splice(index, 1)
    // 自动保存
    await saveToBackend()
  }
}

async function moveUp(row) {
  const index = packages.value.findIndex(p => p.key === row.key)
  if (index > 0) {
    const temp = packages.value[index]
    packages.value[index] = packages.value[index - 1]
    packages.value[index - 1] = temp
    // 自动保存
    await saveToBackend()
  }
}

async function moveDown(row) {
  const index = packages.value.findIndex(p => p.key === row.key)
  if (index < packages.value.length - 1) {
    const temp = packages.value[index]
    packages.value[index] = packages.value[index + 1]
    packages.value[index + 1] = temp
    // 自动保存
    await saveToBackend()
  }
}

async function saveToBackend() {
  loading.value = true
  try {
    await api.updateRechargeConfig({
      packages: packages.value.map((pkg) => ({
        amount: Math.round(Number(pkg.amount) * 100),
        coins: Number(pkg.coins),
        tag: pkg.tag ? pkg.tag.trim() : '',
        tag_color: pkg.tag_color || '#FF5722',
      })),
    })
    message.success('保存成功')
  }
  catch (error) {
    message.error(error?.message || '保存失败')
    console.error(error)
    // 保存失败，重新加载
    await loadConfig()
  }
  finally {
    loading.value = false
  }
}

async function handleSave() {
  await saveToBackend()
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
    title: '角标文字',
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
      return row.tag ? h(NTag, {
        type: 'success',
        size: 'small',
        color: { color: row.tag_color || '#FF5722', textColor: '#fff' }
      }, { default: () => row.tag }) : '-'
    },
  },
  {
    title: '角标颜色',
    key: 'tag_color',
    width: 150,
    render(row) {
      if (row.editable) {
        return h(NColorPicker, {
          value: row.tag_color,
          showAlpha: false,
          modes: ['hex'],
          onUpdateValue: (val) => {
            row.tag_color = val
          },
        })
      }
      return h('div', {
        style: {
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
        },
      }, [
        h('div', {
          style: {
            width: '20px',
            height: '20px',
            borderRadius: '4px',
            backgroundColor: row.tag_color || '#FF5722',
            border: '1px solid #e0e0e6',
          },
        }),
        h('span', {}, row.tag_color || '#FF5722'),
      ])
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
              onClick: () => handleSaveRow(row),
            }, { default: () => '保存' }),
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
      </NSpace>
    </template>

    <NDataTable
      :columns="columns"
      :data="packages"
      :loading="loading"
      :pagination="false"
      :bordered="true"
      :single-line="false"
    />
  </CommonPage>
</template>

<style scoped>
</style>
