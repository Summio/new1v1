<script setup>
import { h, onMounted, ref } from 'vue'
import { NButton, NDataTable, NInputNumber, NPopconfirm, NSpace, useMessage } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import api from '@/api'

defineOptions({ name: '认证用户通话价格档位' })

const message = useMessage()
const loading = ref(false)
const rows = ref([])

onMounted(loadConfig)

async function loadConfig() {
  loading.value = true
  try {
    const res = await api.getCertifiedCallPriceConfig()
    const tiers = Array.isArray(res?.data?.tiers) ? res.data.tiers : [0, 100, 200, 300, 500]
    const normalized = normalizeTiers(tiers)
    rows.value = normalized.map((price) => ({
      key: `tier-${price}`,
      price,
      editable: false,
    }))
  } catch (error) {
    message.error('加载通话价格档位失败')
    rows.value = normalizeTiers([0, 100, 200, 300, 500]).map((price) => ({
      key: `tier-${price}`,
      price,
      editable: false,
    }))
  } finally {
    loading.value = false
  }
}

function normalizeTiers(tiers) {
  const values = Array.from(
    new Set(
      tiers
        .map((item) => Number(item))
        .filter((item) => Number.isInteger(item) && item >= 0)
    )
  ).sort((a, b) => a - b)
  if (!values.includes(0)) values.unshift(0)
  return values
}

function addTier() {
  rows.value.push({
    key: `tier-new-${Date.now()}`,
    price: 100,
    editable: true,
  })
}

function editRow(row) {
  if (row.price === 0) return
  row.editable = true
}

async function saveRow(row) {
  const price = Number(row.price)
  if (!Number.isInteger(price) || price < 0) {
    message.warning('价格必须是非负整数')
    return
  }
  row.price = price
  row.editable = false
  await saveConfig()
}

async function deleteRow(row) {
  if (row.price === 0) {
    message.warning('免费档不能删除')
    return
  }
  rows.value = rows.value.filter((item) => item.key !== row.key)
  await saveConfig()
}

async function saveConfig() {
  loading.value = true
  try {
    const tiers = normalizeTiers(rows.value.map((item) => item.price))
    await api.updateCertifiedCallPriceConfig({ tiers })
    message.success('保存成功')
    rows.value = tiers.map((price) => ({
      key: `tier-${price}`,
      price,
      editable: false,
    }))
  } catch (error) {
    message.error(error?.message || '保存失败')
    await loadConfig()
  } finally {
    loading.value = false
  }
}

const columns = [
  { title: '序号', key: 'index', width: 80, align: 'center', render: (_row, index) => index + 1 },
  {
    title: '价格(分/分钟)',
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
      return price === 0 ? '免费' : `${price / 100}元/分钟`
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
          h(NButton, { size: 'small', type: 'primary', onClick: () => saveRow(row) }, () => '保存'),
          h(NButton, { size: 'small', onClick: loadConfig }, () => '取消'),
        ])
      }
      return h(NSpace, { justify: 'center' }, () => [
        h(
          NButton,
          { size: 'small', disabled: row.price === 0, onClick: () => editRow(row) },
          () => '编辑'
        ),
        h(
          NPopconfirm,
          { onPositiveClick: () => deleteRow(row) },
          {
            trigger: () =>
              h(
                NButton,
                { size: 'small', type: 'error', disabled: row.price === 0 },
                () => '删除'
              ),
            default: () => '确认删除该档位？',
          }
        ),
      ])
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="认证用户通话价格档位">
    <template #action>
      <NButton type="primary" @click="addTier">新增档位</NButton>
    </template>
    <NDataTable :loading="loading" :columns="columns" :data="rows" :pagination="false" />
  </CommonPage>
</template>
