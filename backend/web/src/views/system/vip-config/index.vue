<script setup>
import { h, onMounted, ref } from 'vue'
import {
  NButton,
  NColorPicker,
  NDataTable,
  NInput,
  NInputNumber,
  NPopconfirm,
  NSpace,
  NTag,
  useMessage,
} from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import api from '@/api'

defineOptions({ name: 'VIP配置' })

const message = useMessage()
const loading = ref(false)
const packages = ref([])
const editingKey = ref('')

onMounted(async () => {
  await loadConfig()
})

async function loadConfig() {
  loading.value = true
  try {
    const res = await api.getVipConfig()
    packages.value = Array.isArray(res?.data?.packages)
      ? res.data.packages.map((pkg, index) => ({
          key: `vip-${index}`,
          amount: Number(pkg.amount || 0),
          duration_days: Number(pkg.duration_days || 0),
          label: pkg.label || '',
          tag: pkg.tag || '',
          tag_color: pkg.tag_color || '#D7A84F',
          editable: false,
        }))
      : []
  } catch (error) {
    message.error('加载VIP配置失败')
    console.error(error)
  } finally {
    loading.value = false
  }
}

function addPackage() {
  const newKey = `vip-${Date.now()}`
  packages.value.push({
    key: newKey,
    amount: 1990,
    duration_days: 30,
    label: '月卡',
    tag: '',
    tag_color: '#D7A84F',
    editable: true,
  })
  editingKey.value = newKey
}

function handleEdit(row) {
  editingKey.value = row.key
  row.editable = true
}

async function handleSaveRow(row) {
  const amountYuan = Number(row.amount) / 100
  const days = Number(row.duration_days)
  if (!Number.isFinite(amountYuan) || amountYuan < 0.01) {
    message.error('金额必须大于等于 0.01 元')
    return
  }
  if (!Number.isInteger(days) || days <= 0) {
    message.error('时长必须是大于 0 的整数天')
    return
  }
  if (!String(row.label || '').trim()) {
    message.error('套餐名称不能为空')
    return
  }
  if (row.tag && row.tag.length > 10) {
    message.error('角标最多10个字符')
    return
  }
  row.editable = false
  editingKey.value = ''
  await saveToBackend()
}

function handleCancel(row) {
  if (!row.label) {
    const index = packages.value.findIndex((item) => item.key === row.key)
    if (index > -1) packages.value.splice(index, 1)
  } else {
    row.editable = false
  }
  editingKey.value = ''
}

async function handleDelete(row) {
  const index = packages.value.findIndex((item) => item.key === row.key)
  if (index > -1) {
    packages.value.splice(index, 1)
    await saveToBackend()
  }
}

async function moveUp(row) {
  const index = packages.value.findIndex((item) => item.key === row.key)
  if (index > 0) {
    const current = packages.value[index]
    packages.value[index] = packages.value[index - 1]
    packages.value[index - 1] = current
    await saveToBackend()
  }
}

async function moveDown(row) {
  const index = packages.value.findIndex((item) => item.key === row.key)
  if (index > -1 && index < packages.value.length - 1) {
    const current = packages.value[index]
    packages.value[index] = packages.value[index + 1]
    packages.value[index + 1] = current
    await saveToBackend()
  }
}

async function saveToBackend() {
  if (!packages.value.length) {
    message.error('至少保留一个VIP套餐')
    await loadConfig()
    return
  }
  loading.value = true
  try {
    await api.updateVipConfig({
      packages: packages.value.map((pkg) => ({
        amount: Math.round(Number(pkg.amount || 0)),
        duration_days: Number(pkg.duration_days),
        label: String(pkg.label || '').trim(),
        tag: pkg.tag ? String(pkg.tag).trim() : '',
        tag_color: pkg.tag_color || '#D7A84F',
      })),
    })
    message.success('保存成功')
  } catch (error) {
    message.error(error?.message || '保存失败')
    console.error(error)
    await loadConfig()
  } finally {
    loading.value = false
  }
}

const columns = [
  {
    title: '序号',
    key: 'index',
    width: 80,
    align: 'center',
    render: (_row, index) => index + 1,
  },
  {
    title: '套餐名称',
    key: 'label',
    width: 150,
    render(row) {
      if (!row.editable) return row.label || '-'
      return h(NInput, {
        value: row.label,
        maxlength: 20,
        showCount: true,
        placeholder: '例如: 月卡',
        onUpdateValue: (val) => {
          row.label = val
        },
      })
    },
  },
  {
    title: '金额(元)',
    key: 'amount',
    width: 150,
    render(row) {
      if (!row.editable) return `¥${(Number(row.amount || 0) / 100).toFixed(2)}`
      return h(NInputNumber, {
        value: Number(row.amount || 0) / 100,
        min: 0.01,
        max: 100000,
        step: 1,
        precision: 2,
        style: { width: '100%' },
        onUpdateValue: (val) => {
          row.amount = Math.round(Number(val || 0) * 100)
        },
      })
    },
  },
  {
    title: '时长(天)',
    key: 'duration_days',
    width: 140,
    render(row) {
      if (!row.editable) return `${row.duration_days}天`
      return h(NInputNumber, {
        value: row.duration_days,
        min: 1,
        max: 36500,
        step: 1,
        precision: 0,
        style: { width: '100%' },
        onUpdateValue: (val) => {
          row.duration_days = val
        },
      })
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
          maxlength: 10,
          showCount: true,
          placeholder: '例如: 推荐',
          onUpdateValue: (val) => {
            row.tag = val
          },
        })
      }
      return row.tag
        ? h(
            NTag,
            { size: 'small', color: { color: row.tag_color || '#D7A84F', textColor: '#fff' } },
            { default: () => row.tag }
          )
        : '-'
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
      return row.tag_color || '#D7A84F'
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
        return h(
          NSpace,
          { justify: 'center' },
          {
            default: () => [
              h(
                NButton,
                { size: 'small', type: 'primary', onClick: () => handleSaveRow(row) },
                { default: () => '保存' }
              ),
              h(
                NButton,
                { size: 'small', onClick: () => handleCancel(row) },
                { default: () => '取消' }
              ),
            ],
          }
        )
      }
      return h(
        NSpace,
        { justify: 'center' },
        {
          default: () => [
            h(
              NButton,
              {
                size: 'small',
                type: 'primary',
                secondary: true,
                disabled: editingKey.value !== '',
                onClick: () => handleEdit(row),
              },
              { default: () => '编辑' }
            ),
            h(
              NButton,
              {
                size: 'small',
                disabled: editingKey.value !== '' || index === 0,
                onClick: () => moveUp(row),
              },
              { default: () => '上移' }
            ),
            h(
              NButton,
              {
                size: 'small',
                disabled: editingKey.value !== '' || index === packages.value.length - 1,
                onClick: () => moveDown(row),
              },
              { default: () => '下移' }
            ),
            h(
              NPopconfirm,
              { onPositiveClick: () => handleDelete(row) },
              {
                trigger: () =>
                  h(
                    NButton,
                    {
                      size: 'small',
                      type: 'error',
                      secondary: true,
                      disabled: editingKey.value !== '',
                    },
                    { default: () => '删除' }
                  ),
                default: () => '确认删除该套餐？',
              }
            ),
          ],
        }
      )
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="VIP配置">
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
