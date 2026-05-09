<script setup>
import { computed, h, onMounted, ref } from 'vue'
import {
  NButton,
  NForm,
  NFormItem,
  NImage,
  NInput,
  NInputNumber,
  NModal,
  NSwitch,
  NSpace,
  NTag,
} from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate, renderIcon } from '@/utils'

defineOptions({ name: '礼物管理' })

const $table = ref(null)
const queryItems = ref({})
const editVisible = ref(false)
const saving = ref(false)
const shareSaving = ref(false)
const coinName = ref('金币')
const shareConfigId = ref(null)
const giftAnchorSharePercent = ref(50)
const priceLabel = computed(() => `礼物价格(${coinName.value})`)
const form = ref({
  id: null,
  name: '',
  icon: '',
  svga_url: '',
  price: 1,
  is_active: true,
})

onMounted(() => {
  loadGiftSettings()
  $table.value?.handleSearch()
})

const columns = [
  { title: 'ID', key: 'id', width: 70, align: 'center' },
  {
    title: '图标',
    key: 'icon',
    width: 100,
    align: 'center',
    render(row) {
      if (!row.icon) return '-'
      return h(NImage, {
        src: row.icon,
        width: 40,
        height: 40,
        objectFit: 'cover',
        style: { borderRadius: '8px' },
      })
    },
  },
  { title: '礼物名称', key: 'name', minWidth: 140 },
  {
    title: `价格(${coinName.value})`,
    key: 'price',
    width: 120,
    align: 'center',
  },
  {
    title: 'SVGA',
    key: 'svga_url',
    width: 120,
    align: 'center',
    render(row) {
      if (!row.svga_url) return '-'
      return h(NTag, { type: 'info' }, { default: () => '已上传' })
    },
  },
  {
    title: '状态',
    key: 'is_active',
    width: 90,
    align: 'center',
    render(row) {
      if (row.is_active) {
        return h(NTag, { type: 'success' }, { default: () => '上架' })
      }
      return h(NTag, { type: 'default' }, { default: () => '下架' })
    },
  },
  {
    title: '更新时间',
    key: 'updated_at',
    width: 170,
    align: 'center',
    render(row) {
      return row.updated_at ? formatDate(row.updated_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 180,
    align: 'center',
    render(row) {
      return [
        h(
          NButton,
          {
            type: 'primary',
            size: 'small',
            style: 'margin-right: 8px;',
            onClick: () => handleEdit(row),
          },
          {
            default: () => '编辑',
            icon: renderIcon('material-symbols:edit-outline', { size: 16 }),
          }
        ),
        h(
          NButton,
          {
            type: 'error',
            size: 'small',
            onClick: () => handleDelete(row),
          },
          {
            default: () => '删除',
            icon: renderIcon('material-symbols:delete-outline', { size: 16 }),
          }
        ),
      ]
    },
  },
]

function resetForm() {
  form.value = {
    id: null,
    name: '',
    icon: '',
    svga_url: '',
    price: 1,
    is_active: true,
  }
}

async function fetchData(params = {}) {
  const res = await api.getGiftList({
    page: params.page,
    page_size: params.page_size,
    name: params.name || '',
    is_active: params.is_active === null ? undefined : params.is_active,
  })
  return {
    data: res.data || [],
    total: res.total || 0,
  }
}

async function loadGiftSettings() {
  try {
    const res = await api.getSystemConfigList({ page: 1, page_size: 200 })
    const rows = res.data || []
    const coinRow = rows.find((item) => item.cfg_key === 'coin_name')
    coinName.value = (coinRow?.cfg_value || '金币').toString().trim() || '金币'
    const shareRow = rows.find((item) => item.cfg_key === 'gift_certified_user_share_bps')
    shareConfigId.value = shareRow?.id || null
    const rawBps = Number(shareRow?.cfg_value ?? 5000)
    giftAnchorSharePercent.value = Number.isFinite(rawBps)
      ? Math.min(Math.max(rawBps / 100, 0), 100)
      : 50
    const priceColumn = columns.find((item) => item.key === 'price')
    if (priceColumn) {
      priceColumn.title = `价格(${coinName.value})`
    }
  } catch (_) {
    coinName.value = '金币'
  }
}

async function saveShareConfig() {
  const percent = Number(giftAnchorSharePercent.value)
  if (!Number.isFinite(percent) || percent < 0 || percent > 100) {
    window.$message?.warning('接收方分成需在 0% 到 100% 之间')
    return
  }
  const cfgValue = String(Math.round(percent * 100))
  shareSaving.value = true
  try {
    if (shareConfigId.value) {
      await api.updateSystemConfig({
        id: shareConfigId.value,
        cfg_key: 'gift_certified_user_share_bps',
        cfg_value: cfgValue,
        desc: '礼物接收方分成比例（万分比）',
      })
    } else {
      const res = await api.createSystemConfig({
        cfg_key: 'gift_certified_user_share_bps',
        cfg_value: cfgValue,
        desc: '礼物接收方分成比例（万分比）',
      })
      shareConfigId.value = res?.data?.id || null
    }
    window.$message?.success('分成配置已保存')
  } catch (error) {
    window.$message?.error(error?.message || '分成配置保存失败')
  } finally {
    shareSaving.value = false
  }
}

function handleCreate() {
  resetForm()
  editVisible.value = true
}

function handleEdit(row) {
  form.value = {
    id: row.id,
    name: row.name || '',
    icon: row.icon || '',
    svga_url: row.svga_url || '',
    price: Number(row.price || 1),
    is_active: !!row.is_active,
  }
  editVisible.value = true
}

async function handleDelete(row) {
  try {
    await api.deleteGift({ id: row.id })
    window.$message?.success('删除成功')
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '删除失败')
  }
}

async function submitForm() {
  const payload = {
    name: (form.value.name || '').trim(),
    icon: (form.value.icon || '').trim(),
    svga_url: (form.value.svga_url || '').trim() || null,
    price: Number(form.value.price || 0),
    is_active: !!form.value.is_active,
  }
  if (!payload.name) {
    window.$message?.warning('请输入礼物名称')
    return
  }
  if (!Number.isFinite(payload.price) || payload.price <= 0) {
    window.$message?.warning(`礼物价格必须大于0（单位：${coinName.value}）`)
    return
  }
  if (!Number.isInteger(payload.price)) {
    window.$message?.warning('礼物价格必须为整数')
    return
  }

  saving.value = true
  try {
    if (form.value.id) {
      await api.updateGift({
        id: form.value.id,
        ...payload,
      })
      window.$message?.success('更新成功')
    } else {
      await api.createGift(payload)
      window.$message?.success('创建成功')
    }
    editVisible.value = false
    $table.value?.handleSearch()
  } catch (error) {
    window.$message?.error(error?.message || '保存失败')
  } finally {
    saving.value = false
  }
}

function chooseFile(accept) {
  return new Promise((resolve) => {
    const input = document.createElement('input')
    input.type = 'file'
    input.accept = accept
    input.onchange = () => {
      const file = input.files && input.files.length ? input.files[0] : null
      resolve(file)
    }
    input.click()
  })
}

async function uploadResource(file, type) {
  if (!file) return ''
  const formData = new FormData()
  formData.append('file', file)
  const res = await api.uploadGiftResource(formData, { resource_type: type })
  return res?.data?.url || ''
}

async function handleUploadIcon() {
  try {
    const file = await chooseFile('image/png,image/jpeg,image/webp')
    if (!file) return
    const url = await uploadResource(file, 'icon')
    if (!url) return
    form.value.icon = url
    window.$message?.success('图标上传成功')
  } catch (error) {
    window.$message?.error(error?.message || '图标上传失败')
  }
}

function handleRemoveIcon() {
  form.value.icon = ''
}

async function handleUploadSvga() {
  try {
    const file = await chooseFile('.svga')
    if (!file) return
    const url = await uploadResource(file, 'svga')
    if (!url) return
    form.value.svga_url = url
    window.$message?.success('SVGA 上传成功')
  } catch (error) {
    window.$message?.error(error?.message || 'SVGA 上传失败')
  }
}

function handleRemoveSvga() {
  form.value.svga_url = ''
}

function getResourceName(url) {
  const value = (url || '').trim()
  if (!value) return ''
  const pathname = value.split('?')[0].split('#')[0]
  return pathname.split('/').filter(Boolean).pop() || value
}
</script>

<template>
  <CommonPage show-footer title="礼物管理">
    <template #action>
      <NSpace align="center">
        <NInputNumber
          v-model:value="giftAnchorSharePercent"
          :min="0"
          :max="100"
          :step="1"
          :precision="2"
          :show-button="false"
          style="width: 150px"
          placeholder="接收方分成"
        >
          <template #suffix>%</template>
        </NInputNumber>
        <NButton secondary type="primary" :loading="shareSaving" @click="saveShareConfig">
          保存分成
        </NButton>
        <NButton type="primary" @click="handleCreate">新增礼物</NButton>
      </NSpace>
    </template>

    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="fetchData"
      :scroll-x="1180"
    >
      <template #queryBar>
        <QueryBarItem label="礼物名称">
          <NInput v-model:value="queryItems.name" clearable placeholder="请输入礼物名称" />
        </QueryBarItem>
      </template>
    </CrudTable>

    <NModal
      v-model:show="editVisible"
      preset="card"
      title="礼物信息"
      :style="{ width: '480px', maxWidth: 'calc(100vw - 32px)' }"
    >
      <NForm label-placement="left" label-width="96">
        <NFormItem label="礼物名称">
          <NInput v-model:value="form.name" placeholder="请输入礼物名称" />
        </NFormItem>
        <NFormItem :label="priceLabel">
          <NInputNumber
            v-model:value="form.price"
            :min="1"
            :max="99999999"
            :step="1"
            :precision="0"
          />
        </NFormItem>
        <NFormItem label="礼物图标">
          <div class="resource-field">
            <NImage
              v-if="form.icon"
              :src="form.icon"
              width="72"
              height="72"
              object-fit="cover"
              class="icon-preview"
            />
            <div v-else class="empty-preview">暂无图标</div>
            <div class="resource-actions">
              <NButton secondary type="primary" @click="handleUploadIcon">上传图标</NButton>
              <NButton v-if="form.icon" secondary type="error" @click="handleRemoveIcon">
                移除
              </NButton>
            </div>
          </div>
        </NFormItem>
        <NFormItem label="SVGA资源">
          <div class="resource-field">
            <div v-if="form.svga_url" class="svga-preview">
              <div class="svga-badge">SVGA</div>
              <div class="svga-name">{{ getResourceName(form.svga_url) }}</div>
            </div>
            <div v-else class="empty-preview">暂无SVGA</div>
            <div class="resource-actions">
              <NButton secondary type="primary" @click="handleUploadSvga">上传SVGA</NButton>
              <NButton v-if="form.svga_url" secondary type="error" @click="handleRemoveSvga">
                移除
              </NButton>
            </div>
          </div>
        </NFormItem>
        <NFormItem label="上架状态">
          <NSwitch v-model:value="form.is_active" />
        </NFormItem>
      </NForm>
      <template #footer>
        <div class="modal-footer">
          <NButton @click="editVisible = false">取消</NButton>
          <NButton type="primary" :loading="saving" @click="submitForm">保存</NButton>
        </div>
      </template>
    </NModal>
  </CommonPage>
</template>

<style scoped>
.resource-field {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
}

.icon-preview {
  border-radius: 8px;
}

.empty-preview,
.svga-preview {
  width: 72px;
  height: 72px;
  border: 1px dashed #d9d9e3;
  border-radius: 8px;
  background: #fafafa;
}

.empty-preview {
  display: flex;
  align-items: center;
  justify-content: center;
  color: #8b8f99;
  font-size: 12px;
}

.svga-preview {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 8px;
  border-style: solid;
}

.svga-badge {
  margin-bottom: 6px;
  color: #18a058;
  font-size: 13px;
  font-weight: 600;
}

.svga-name {
  max-width: 100%;
  overflow: hidden;
  color: #606266;
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.resource-actions {
  display: flex;
  gap: 8px;
}

.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
}
</style>
