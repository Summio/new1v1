<script setup>
import { h, onMounted, ref } from 'vue'
import { NButton, NForm, NFormItem, NImage, NInput, NInputNumber, NModal, NSelect, NSwitch, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate } from '@/utils'

defineOptions({ name: 'App用户管理' })

const $table = ref(null)
const queryItems = ref({})
const editModalVisible = ref(false)
const saving = ref(false)
const modalForm = ref({
  id: null,
  phone: '',
  nickname: '',
  avatar: '',
  gender: 'secret',
  birth_date: '',
  height_cm: null,
  weight_kg: null,
  location_city: '',
  status: 'normal',
  is_anchor: false,
  cover_url: '',
  album_photos: [],
})

onMounted(() => {
  $table.value?.handleSearch()
})

const statusOptions = [
  { label: '正常', value: 'normal' },
  { label: '封禁', value: 'banned' },
]

const genderOptions = [
  { label: '男', value: 'male' },
  { label: '女', value: 'female' },
  { label: '保密', value: 'secret' },
]

const anchorOptions = [
  { label: '主播', value: true },
  { label: '普通用户', value: false },
]

const avatarImgStyle = {
  width: '44px',
  height: '44px',
  minWidth: '44px',
  minHeight: '44px',
  maxWidth: '44px',
  maxHeight: '44px',
  borderRadius: '8px',
  objectFit: 'cover',
  border: '1px solid #eceff5',
  display: 'block',
}

const coverImgStyle = {
  width: '36px',
  height: '36px',
  minWidth: '36px',
  minHeight: '36px',
  maxWidth: '36px',
  maxHeight: '36px',
  borderRadius: '8px',
  objectFit: 'cover',
  border: '1px solid #eceff5',
  display: 'block',
}

function normalizeAlbum(v) {
  if (!Array.isArray(v)) return []
  return v.filter(item => typeof item === 'string' && item.trim()).map(item => item.trim())
}

function infoLine(label, value) {
  return h('div', { class: 'meta-line' }, [
    h('span', { class: 'meta-label' }, `${label}：`),
    h('span', { class: 'meta-value' }, value || '-'),
  ])
}

function openEditModal(row) {
  const album = normalizeAlbum(row.album_photos)
  modalForm.value = {
    id: row.id,
    phone: row.phone || '',
    nickname: row.nickname || '',
    avatar: row.avatar || '',
    gender: row.gender || 'secret',
    birth_date: row.birth_date || '',
    height_cm: row.height_cm ?? null,
    weight_kg: row.weight_kg ?? null,
    location_city: row.location_city || '',
    status: row.status || 'normal',
    is_anchor: !!row.is_anchor,
    cover_url: row.cover_url || '',
    album_photos: album,
  }
  editModalVisible.value = true
}

function handleViewEdit(row) {
  openEditModal(row)
}

async function handleSave() {
  if (!modalForm.value.id) return
  saving.value = true
  try {
    const album = normalizeAlbum(modalForm.value.album_photos)
    const payload = {
      id: modalForm.value.id,
      nickname: (modalForm.value.nickname || '').trim(),
      avatar: (modalForm.value.avatar || '').trim(),
      gender: modalForm.value.gender || 'secret',
      birth_date: (modalForm.value.birth_date || '').trim() || null,
      height_cm: modalForm.value.height_cm ?? null,
      weight_kg: modalForm.value.weight_kg ?? null,
      location_city: (modalForm.value.location_city || '').trim(),
      status: modalForm.value.status || 'normal',
      is_anchor: !!modalForm.value.is_anchor,
      album_photos: album,
      cover_url: (modalForm.value.cover_url || '').trim(),
    }
    await api.updateAppUser(payload)
    $message?.success('保存成功')
    editModalVisible.value = false
    $table.value?.handleSearch()
  } catch (error) {
    $message?.error(error?.message || '保存失败')
  } finally {
    saving.value = false
  }
}

function chooseImageFile() {
  return new Promise(resolve => {
    const input = document.createElement('input')
    input.type = 'file'
    input.accept = 'image/png,image/jpeg,image/webp'
    input.onchange = () => {
      const file = input.files && input.files.length ? input.files[0] : null
      resolve(file)
    }
    input.click()
  })
}

async function uploadImage(file) {
  if (!file) return ''
  const formData = new FormData()
  formData.append('file', file)
  const res = await api.uploadAppUserImage(formData)
  return res?.data?.url || ''
}

async function handleUploadAvatar() {
  try {
    const file = await chooseImageFile()
    if (!file) return
    const url = await uploadImage(file)
    if (!url) return
    modalForm.value.avatar = url
    window.$message?.success('头像上传成功')
  } catch (error) {
    window.$message?.error(error?.message || '头像上传失败')
  }
}

async function handleAddAlbumPhoto() {
  if ((modalForm.value.album_photos || []).length >= 6) {
    window.$message?.warning('相册最多6张')
    return
  }
  try {
    const file = await chooseImageFile()
    if (!file) return
    const url = await uploadImage(file)
    if (!url) return
    modalForm.value.album_photos = [...(modalForm.value.album_photos || []), url]
    if (!modalForm.value.cover_url) {
      modalForm.value.cover_url = url
    }
    window.$message?.success('相册上传成功')
  } catch (error) {
    window.$message?.error(error?.message || '相册上传失败')
  }
}

async function handleReplaceAlbumPhoto(index) {
  try {
    const file = await chooseImageFile()
    if (!file) return
    const url = await uploadImage(file)
    if (!url) return
    const next = [...(modalForm.value.album_photos || [])]
    const old = next[index]
    next[index] = url
    modalForm.value.album_photos = next
    if (modalForm.value.cover_url === old) {
      modalForm.value.cover_url = url
    }
    window.$message?.success('照片已替换')
  } catch (error) {
    window.$message?.error(error?.message || '替换失败')
  }
}

function handleRemoveAlbumPhoto(index) {
  const next = [...(modalForm.value.album_photos || [])]
  const removed = next[index]
  next.splice(index, 1)
  modalForm.value.album_photos = next
  if (modalForm.value.cover_url === removed) {
    modalForm.value.cover_url = next[0] || ''
  }
}

function handleSetCover(url) {
  modalForm.value.cover_url = url || ''
}

const columns = [
  { title: 'ID', key: 'id', width: 60, align: 'center' },
  {
    title: '头像',
    key: 'avatar',
    width: 86,
    align: 'center',
    render(row) {
      if (!row.avatar) return '-'
      return h(NImage, {
        src: row.avatar,
        width: 44,
        height: 44,
        objectFit: 'cover',
        previewDisabled: false,
        imgProps: {
          class: 'avatar-thumb',
          style: avatarImgStyle,
          alt: 'avatar',
        },
      })
    },
  },
  {
    title: '账号信息',
    key: 'account',
    width: 200,
    render(row) {
      return h('div', { class: 'meta-wrap' }, [
        infoLine('手机号', row.phone || '-'),
        infoLine('昵称', row.nickname || '-'),
      ])
    },
  },
  {
    title: '资料信息',
    key: 'profile',
    width: 260,
    render(row) {
      const genderMap = { male: '男', female: '女', secret: '保密' }
      const hw = [row.height_cm ? `${row.height_cm}cm` : '', row.weight_kg ? `${row.weight_kg}kg` : '']
        .filter(Boolean)
        .join(' / ')
      return h('div', { class: 'meta-wrap' }, [
        infoLine('性别', genderMap[row.gender] || '保密'),
        infoLine('生日', row.birth_date || '-'),
        infoLine('身高体重', hw || '-'),
        infoLine('所在地', row.location_city || '-'),
      ])
    },
  },
  {
    title: '相册/封面',
    key: 'album_cover',
    width: 220,
    render(row) {
      const album = normalizeAlbum(row.album_photos)
      const cover = row.cover_url || ''
      return h('div', { class: 'album-summary' }, [
        h('div', { class: 'album-summary-top' }, [
          cover
            ? h(NImage, {
                src: cover,
                width: 36,
                height: 36,
                objectFit: 'cover',
                previewDisabled: false,
                imgProps: {
                  class: 'cover-thumb',
                  style: coverImgStyle,
                  alt: 'cover',
                },
              })
            : h('div', { class: 'cover-placeholder' }, '无封面'),
          h('div', { class: 'album-summary-meta' }, [
            h('div', { class: 'album-head' }, `相册 ${album.length} 张`),
            h('div', { class: 'album-sub' }, cover ? '已设置封面' : '未设置封面'),
          ]),
        ]),
      ])
    },
  },
  {
    title: '状态',
    key: 'status',
    width: 80,
    align: 'center',
    render(row) {
      const isBanned = row.status === 'banned'
      return h(
        NTag,
        { type: isBanned ? 'error' : 'success' },
        { default: () => (isBanned ? '封禁' : '正常') }
      )
    },
  },
  {
    title: '主播',
    key: 'is_anchor',
    width: 70,
    align: 'center',
    render(row) {
      return h(
        NTag,
        { type: row.is_anchor ? 'warning' : 'default' },
        { default: () => (row.is_anchor ? '是' : '否') }
      )
    },
  },
  { title: '金币', key: 'coins', width: 90, align: 'center' },
  { title: '钻石', key: 'diamonds', width: 90, align: 'center' },
  { title: '冻结钻石', key: 'frozen_diamonds', width: 100, align: 'center' },
  {
    title: '创建时间',
    key: 'created_at',
    width: 140,
    align: 'center',
    render(row) {
      return row.created_at ? formatDate(row.created_at) : ''
    },
  },
  {
    title: '最后登录',
    key: 'last_login',
    width: 140,
    align: 'center',
    render(row) {
      return row.last_login ? formatDate(row.last_login) : ''
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 100,
    align: 'center',
    fixed: 'right',
    render(row) {
      return h(
        NButton,
        {
          size: 'small',
          type: 'primary',
          onClick: () => handleViewEdit(row),
        },
        { default: () => '查看/编辑' }
      )
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="App用户列表">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="api.getAppUserList"
    >
      <template #queryBar>
        <QueryBarItem label="手机号" :label-width="60">
          <NInput
            v-model:value="queryItems.phone"
            clearable
            type="text"
            placeholder="请输入手机号"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="昵称" :label-width="50">
          <NInput
            v-model:value="queryItems.nickname"
            clearable
            type="text"
            placeholder="请输入昵称"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="性别" :label-width="50">
          <NSelect
            v-model:value="queryItems.gender"
            clearable
            style="width: 140px"
            :options="genderOptions"
            placeholder="请选择性别"
          />
        </QueryBarItem>
        <QueryBarItem label="所在地" :label-width="60">
          <NInput
            v-model:value="queryItems.location_city"
            clearable
            type="text"
            placeholder="请输入城市"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="状态" :label-width="50">
          <NSelect
            v-model:value="queryItems.status"
            clearable
            style="width: 160px"
            :options="statusOptions"
            placeholder="请选择状态"
          />
        </QueryBarItem>
        <QueryBarItem label="主播" :label-width="50">
          <NSelect
            v-model:value="queryItems.is_anchor"
            clearable
            style="width: 160px"
            :options="anchorOptions"
            placeholder="请选择类型"
          />
        </QueryBarItem>
      </template>
    </CrudTable>

    <NModal v-model:show="editModalVisible" preset="card" title="查看/编辑 App用户" style="width: 860px">
      <NForm label-placement="left" label-width="90" class="edit-form-grid">
        <NFormItem label="用户ID">
          <NInput :value="String(modalForm.id || '')" readonly />
        </NFormItem>
        <NFormItem label="手机号">
          <NInput v-model:value="modalForm.phone" readonly />
        </NFormItem>
        <NFormItem label="昵称">
          <NInput v-model:value="modalForm.nickname" />
        </NFormItem>
        <NFormItem label="性别">
          <NSelect v-model:value="modalForm.gender" :options="genderOptions" />
        </NFormItem>
        <NFormItem label="出生日期">
          <NInput v-model:value="modalForm.birth_date" placeholder="YYYY-MM-DD" />
        </NFormItem>
        <NFormItem label="所在地">
          <NInput v-model:value="modalForm.location_city" placeholder="省-市" />
        </NFormItem>
        <NFormItem label="身高(cm)">
          <NInputNumber v-model:value="modalForm.height_cm" style="width: 100%" clearable />
        </NFormItem>
        <NFormItem label="体重(kg)">
          <NInputNumber v-model:value="modalForm.weight_kg" style="width: 100%" clearable />
        </NFormItem>
        <NFormItem label="状态">
          <NSelect v-model:value="modalForm.status" :options="statusOptions" />
        </NFormItem>
        <NFormItem label="主播">
          <NSwitch v-model:value="modalForm.is_anchor" />
        </NFormItem>

        <NFormItem label="头像" class="full-span">
          <div class="media-row">
            <div class="media-thumb-lg">
              <NImage
                v-if="modalForm.avatar"
                :src="modalForm.avatar"
                width="92"
                height="92"
                object-fit="cover"
              />
              <span v-else>暂无头像</span>
            </div>
            <NButton type="primary" secondary @click="handleUploadAvatar">上传头像</NButton>
          </div>
        </NFormItem>
        <NFormItem label="封面" class="full-span">
          <div class="media-row">
            <div class="media-thumb-lg">
              <NImage
                v-if="modalForm.cover_url"
                :src="modalForm.cover_url"
                width="92"
                height="92"
                object-fit="cover"
              />
              <span v-else>未设置封面</span>
            </div>
            <NSelect
              v-model:value="modalForm.cover_url"
              :options="(modalForm.album_photos || []).map((item, idx) => ({ label: `相册图 ${idx + 1}`, value: item }))"
              placeholder="从相册中选择封面"
              clearable
              style="width: 220px"
            />
          </div>
        </NFormItem>
        <NFormItem label="相册" class="full-span">
          <div class="album-editor">
            <div class="album-actions">
              <NButton type="primary" secondary @click="handleAddAlbumPhoto">新增照片</NButton>
              <span class="hint">最多6张，点击“设为封面”即可切换封面</span>
            </div>
            <div v-if="(modalForm.album_photos || []).length" class="album-grid">
              <div v-for="(url, idx) in modalForm.album_photos" :key="`${url}-${idx}`" class="album-card">
                <div class="media-thumb-md">
                  <NImage :src="url" width="100%" height="120" object-fit="cover" />
                </div>
                <div class="album-btns">
                  <NButton size="tiny" @click="handleReplaceAlbumPhoto(idx)">更换</NButton>
                  <NButton size="tiny" type="info" @click="handleSetCover(url)">
                    {{ modalForm.cover_url === url ? '当前封面' : '设为封面' }}
                  </NButton>
                  <NButton size="tiny" type="error" @click="handleRemoveAlbumPhoto(idx)">删除</NButton>
                </div>
              </div>
            </div>
            <div v-else class="hint">暂无相册图片</div>
          </div>
        </NFormItem>
      </NForm>

      <template #action>
        <NButton @click="editModalVisible = false">取消</NButton>
        <NButton type="primary" :loading="saving" style="margin-left: 8px" @click="handleSave">
          保存
        </NButton>
      </template>
    </NModal>
  </CommonPage>
</template>

<style scoped>
.avatar-thumb {
  width: 44px;
  height: 44px;
  border-radius: 8px;
  object-fit: cover;
  border: 1px solid #eceff5;
}

.meta-wrap {
  display: flex;
  flex-direction: column;
  gap: 4px;
  line-height: 1.3;
}

.meta-line {
  display: flex;
  align-items: baseline;
}

.meta-label {
  color: #8b8f99;
  flex-shrink: 0;
}

.meta-value {
  color: #242933;
  word-break: break-all;
}

.album-head {
  color: #242933;
  font-weight: 600;
  white-space: nowrap;
  text-overflow: ellipsis;
  overflow: hidden;
}

.album-summary {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.album-summary-top {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.album-summary-meta {
  min-width: 0;
}

.album-sub {
  color: #8b8f99;
  font-size: 12px;
}

.cover-placeholder {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  border: 1px dashed #d7dbe3;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #8b8f99;
  font-size: 10px;
}

.cover-row {
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  overflow: hidden;
}

.cover-thumb {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  object-fit: cover;
  border: 1px solid #eceff5;
  flex: 0 0 auto;
}

.edit-form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  column-gap: 16px;
}

.full-span {
  grid-column: 1 / -1;
}

.media-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.media-thumb-lg {
  width: 92px;
  height: 92px;
  border: 1px dashed #d7dbe3;
  border-radius: 10px;
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #8b8f99;
  font-size: 12px;
}

.media-thumb-lg img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.album-editor {
  width: 100%;
}

.album-actions {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 10px;
}

.hint {
  color: #8b8f99;
  font-size: 12px;
}

.album-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 10px;
}

.album-card {
  border: 1px solid #edf0f5;
  border-radius: 8px;
  padding: 8px;
}

.media-thumb-md {
  width: 100%;
  height: 120px;
  border-radius: 8px;
  overflow: hidden;
  background: #f7f8fb;
}

.media-thumb-md img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.album-btns {
  margin-top: 8px;
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
}

</style>
