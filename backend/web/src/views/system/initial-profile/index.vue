<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import {
  NButton,
  NCard,
  NEmpty,
  NGrid,
  NGridItem,
  NInput,
  NModal,
  NRadio,
  NRadioGroup,
  NScrollbar,
  NSpace,
  NTabPane,
  NTabs,
  useMessage,
} from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import { renderIcon } from '@/utils'
import api from '@/api'
import { nicknameUploadTargets, resolveNicknameUploadTarget } from './nickname-upload-targets.mjs'

defineOptions({ name: '初始资料管理' })

const message = useMessage()
const loading = ref(false)
const saving = ref(false)
const uploadDialogVisible = ref(false)
const uploadTargetGender = ref('male')
const nicknameUploadDialogVisible = ref(false)
const nicknameUploadTarget = ref('male-prefixes')
const nicknameUploadContent = ref('')
const avatarUploadRefs = {
  male: ref(null),
  female: ref(null),
}

const state = reactive({
  avatarPool: { male: [], female: [] },
  nicknamePool: {
    male: { prefixes: [], suffixes: [] },
    female: { prefixes: [], suffixes: [] },
  },
  selectedAvatars: {
    male: [],
    female: [],
  },
  selectedNicknames: {
    male: { prefixes: [], suffixes: [] },
    female: { prefixes: [], suffixes: [] },
  },
})

const genderMeta = {
  male: { label: '男生', color: '#2080f0' },
  female: { label: '女生', color: '#d03050' },
}

const stats = computed(() => {
  const malePrefix = state.nicknamePool.male.prefixes.length
  const maleSuffix = state.nicknamePool.male.suffixes.length
  const femalePrefix = state.nicknamePool.female.prefixes.length
  const femaleSuffix = state.nicknamePool.female.suffixes.length
  return [
    { label: '男头像', value: state.avatarPool.male.length },
    { label: '女头像', value: state.avatarPool.female.length },
    { label: '男前缀', value: malePrefix },
    { label: '男后缀', value: maleSuffix },
    { label: '女前缀', value: femalePrefix },
    { label: '女后缀', value: femaleSuffix },
    {
      label: '可组合昵称',
      value: malePrefix * maleSuffix + femalePrefix * femaleSuffix,
    },
  ]
})

const nicknameUploadPlaceholder = computed(() => {
  const { section } = resolveNicknameUploadTarget(nicknameUploadTarget.value)
  return section === 'prefixes'
    ? '用、隔开多个前缀，例如：阳光、清爽、温柔'
    : '用、隔开多个后缀，例如：少年、先生、小哥'
})

onMounted(loadConfig)

async function loadConfig() {
  loading.value = true
  try {
    const res = await api.getInitialProfileConfig()
    const data = res.data || {}
    state.avatarPool = normalizeAvatarPool(data.avatar_pool)
    state.nicknamePool = normalizeNicknamePool(data.nickname_pool)
    state.selectedAvatars.male = []
    state.selectedAvatars.female = []
    state.selectedNicknames.male.prefixes = []
    state.selectedNicknames.male.suffixes = []
    state.selectedNicknames.female.prefixes = []
    state.selectedNicknames.female.suffixes = []
  } catch (error) {
    message.error('加载初始资料配置失败')
    console.error(error)
  } finally {
    loading.value = false
  }
}

function normalizeAvatarPool(pool = {}) {
  return {
    male: Array.isArray(pool.male) ? [...pool.male] : [],
    female: Array.isArray(pool.female) ? [...pool.female] : [],
  }
}

function normalizeNicknamePool(pool = {}) {
  return {
    male: {
      prefixes: Array.isArray(pool.male?.prefixes) ? [...pool.male.prefixes] : [],
      suffixes: Array.isArray(pool.male?.suffixes) ? [...pool.male.suffixes] : [],
    },
    female: {
      prefixes: Array.isArray(pool.female?.prefixes) ? [...pool.female.prefixes] : [],
      suffixes: Array.isArray(pool.female?.suffixes) ? [...pool.female.suffixes] : [],
    },
  }
}

function openAvatarPicker(gender) {
  avatarUploadRefs[gender].value?.click()
}

function openUploadDialog(defaultGender = 'male') {
  uploadTargetGender.value = defaultGender
  uploadDialogVisible.value = true
}

function confirmUploadTarget() {
  uploadDialogVisible.value = false
  openAvatarPicker(uploadTargetGender.value)
}

function openNicknameUploadDialog(defaultTarget = 'male-prefixes') {
  nicknameUploadTarget.value = defaultTarget
  nicknameUploadContent.value = ''
  nicknameUploadDialogVisible.value = true
}

function closeNicknameUploadDialog() {
  nicknameUploadDialogVisible.value = false
  nicknameUploadContent.value = ''
}

async function handleAvatarFilesChange(gender, event) {
  const files = Array.from(event.target.files || [])
  event.target.value = ''
  if (!files.length) return

  const formData = new FormData()
  formData.append('gender', gender)
  files.forEach((file) => {
    formData.append('files', file)
  })

  saving.value = true
  try {
    const res = await api.uploadInitialProfileAvatar(formData, { gender })
    const payload = res.data || {}
    const failed = Array.isArray(payload.failed) ? payload.failed : []
    const uploaded = Array.isArray(payload.uploaded) ? payload.uploaded : []
    if (uploaded.length) {
      message.success(`已上传 ${uploaded.length} 张头像`)
    }
    if (failed.length) {
      message.warning(`有 ${failed.length} 张头像上传失败`)
    }
    await loadConfig()
  } catch (error) {
    message.error(error?.message || '上传失败')
    console.error(error)
  } finally {
    saving.value = false
  }
}

async function saveAvatarPool() {
  saving.value = true
  try {
    await api.updateInitialProfileAvatarPool({
      male: state.avatarPool.male,
      female: state.avatarPool.female,
    })
    message.success('头像池已保存')
  } catch (error) {
    message.error(error?.message || '保存失败')
    console.error(error)
    await loadConfig()
  } finally {
    saving.value = false
  }
}

async function removeSelectedAvatars(gender) {
  const selected = new Set(state.selectedAvatars[gender])
  if (!selected.size) return
  state.avatarPool[gender] = state.avatarPool[gender].filter((item) => !selected.has(item))
  state.selectedAvatars[gender] = []
  await saveAvatarPool()
}

function toggleAvatar(gender, url) {
  const picked = state.selectedAvatars[gender]
  state.selectedAvatars[gender] = picked.includes(url)
    ? picked.filter((item) => item !== url)
    : [...picked, url]
}

async function saveNicknamePool() {
  saving.value = true
  try {
    await api.updateInitialProfileNicknamePool({
      male: state.nicknamePool.male,
      female: state.nicknamePool.female,
    })
    message.success('昵称池已保存')
  } catch (error) {
    message.error(error?.message || '保存失败')
    console.error(error)
    await loadConfig()
  } finally {
    saving.value = false
  }
}

function toggleNickname(gender, section, value) {
  const picked = state.selectedNicknames[gender][section]
  state.selectedNicknames[gender][section] = picked.includes(value)
    ? picked.filter((item) => item !== value)
    : [...picked, value]
}

async function removeSelectedNicknames(gender, section) {
  const selected = new Set(state.selectedNicknames[gender][section])
  if (!selected.size) return
  state.nicknamePool[gender][section] = state.nicknamePool[gender][section].filter(
    (item) => !selected.has(item)
  )
  state.selectedNicknames[gender][section] = []
  await saveNicknamePool()
}

async function importNickname(gender, section, content) {
  if (!content.trim()) {
    message.warning('请先输入素材')
    return false
  }
  saving.value = true
  try {
    const res = await api.importInitialProfileNickname({
      gender,
      section,
      content,
    })
    const added = res.data?.added ?? 0
    message.success(`已导入 ${added} 条素材`)
    await loadConfig()
    return true
  } catch (error) {
    message.error(error?.message || '导入失败')
    console.error(error)
    return false
  } finally {
    saving.value = false
  }
}

async function submitNicknameUpload() {
  const { gender, section } = resolveNicknameUploadTarget(nicknameUploadTarget.value)
  const content = nicknameUploadContent.value
  const imported = await importNickname(gender, section, content)
  if (imported) {
    closeNicknameUploadDialog()
  }
}
</script>

<template>
  <CommonPage title="初始资料管理" show-footer>
    <div class="summary-row">
      <div v-for="item in stats" :key="item.label" class="summary-item">
        <div class="summary-label">{{ item.label }}</div>
        <div class="summary-value">{{ item.value }}</div>
      </div>
    </div>

    <NTabs type="line" animated>
      <NTabPane name="avatar" tab="头像池">
        <NSpace vertical size="large">
          <div class="toolbar-row">
            <NButton :loading="saving" type="primary" @click="openUploadDialog()">
              <template #icon>
                <component :is="renderIcon('material-symbols:upload')" />
              </template>
              上传
            </NButton>
          </div>
          <NCard v-for="gender in ['male', 'female']" :key="gender" size="small" :bordered="false">
            <template #header>
              <div class="panel-header">
                <div>
                  <div class="panel-title">{{ genderMeta[gender].label }}头像</div>
                  <div class="panel-subtitle">批量上传、按选中删除、直接保存分组结果</div>
                </div>
                <NSpace>
                  <NButton
                    :disabled="!state.selectedAvatars[gender].length"
                    :loading="saving"
                    tertiary
                    type="error"
                    @click="removeSelectedAvatars(gender)"
                  >
                    <template #icon>
                      <component :is="renderIcon('material-symbols:delete-outline')" />
                    </template>
                    删除选中
                  </NButton>
                </NSpace>
              </div>
            </template>

            <input
              :ref="(el) => (avatarUploadRefs[gender].value = el)"
              class="hidden-file-input"
              accept=".jpg,.jpeg,.png,.webp"
              multiple
              type="file"
              @change="(event) => handleAvatarFilesChange(gender, event)"
            />

            <NScrollbar style="max-height: 560px">
              <NEmpty
                v-if="!state.avatarPool[gender].length"
                :description="`${genderMeta[gender].label}头像池暂无素材`"
              />
              <NGrid v-else cols="2 560:4 860:6 1180:8 1440:10" :x-gap="10" :y-gap="10">
                <NGridItem v-for="url in state.avatarPool[gender]" :key="url">
                  <div
                    class="avatar-item"
                    :class="{
                      'avatar-item--selected': state.selectedAvatars[gender].includes(url),
                    }"
                    @click="toggleAvatar(gender, url)"
                  >
                    <img :src="url" alt="头像素材" />
                  </div>
                </NGridItem>
              </NGrid>
            </NScrollbar>
          </NCard>
        </NSpace>
      </NTabPane>

      <NTabPane name="nickname" tab="昵称池">
        <NSpace vertical size="large">
          <div class="toolbar-row">
            <NButton :loading="saving" type="primary" @click="openNicknameUploadDialog()">
              <template #icon>
                <component :is="renderIcon('material-symbols:upload')" />
              </template>
              上传
            </NButton>
          </div>
          <NCard v-for="gender in ['male', 'female']" :key="gender" size="small" :bordered="false">
            <template #header>
              <div class="panel-header">
                <div>
                  <div class="panel-title">{{ genderMeta[gender].label }}昵称</div>
                  <div class="panel-subtitle">前缀和后缀分开维护，批量粘贴后自动去重</div>
                </div>
              </div>
            </template>

            <div class="nickname-layout">
              <div class="nickname-column">
                <div class="column-header">
                  <div class="column-title">前缀列表</div>
                  <NButton
                    :disabled="!state.selectedNicknames[gender].prefixes.length"
                    :loading="saving"
                    tertiary
                    type="error"
                    size="small"
                    @click="removeSelectedNicknames(gender, 'prefixes')"
                  >
                    删除选中
                  </NButton>
                </div>
                <div class="tag-panel">
                  <NEmpty
                    v-if="!state.nicknamePool[gender].prefixes.length"
                    description="暂无素材"
                  />
                  <div v-else class="tag-flow">
                    <button
                      v-for="item in state.nicknamePool[gender].prefixes"
                      :key="item"
                      type="button"
                      class="nickname-chip nickname-chip--prefix"
                      :class="{
                        'nickname-chip--selected':
                          state.selectedNicknames[gender].prefixes.includes(item),
                      }"
                      @click="toggleNickname(gender, 'prefixes', item)"
                    >
                      {{ item }}
                    </button>
                  </div>
                </div>
              </div>

              <div class="nickname-column">
                <div class="column-header">
                  <div class="column-title">后缀列表</div>
                  <NButton
                    :disabled="!state.selectedNicknames[gender].suffixes.length"
                    :loading="saving"
                    tertiary
                    type="error"
                    size="small"
                    @click="removeSelectedNicknames(gender, 'suffixes')"
                  >
                    删除选中
                  </NButton>
                </div>
                <div class="tag-panel">
                  <NEmpty
                    v-if="!state.nicknamePool[gender].suffixes.length"
                    description="暂无素材"
                  />
                  <div v-else class="tag-flow">
                    <button
                      v-for="item in state.nicknamePool[gender].suffixes"
                      :key="item"
                      type="button"
                      class="nickname-chip nickname-chip--suffix"
                      :class="{
                        'nickname-chip--selected':
                          state.selectedNicknames[gender].suffixes.includes(item),
                      }"
                      @click="toggleNickname(gender, 'suffixes', item)"
                    >
                      {{ item }}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </NCard>
        </NSpace>
      </NTabPane>
    </NTabs>

    <template #footer>
      <div class="page-footer-hint">头像和昵称仅支持运营素材池，不支持用户自定义。</div>
    </template>
  </CommonPage>

  <NModal
    v-model:show="uploadDialogVisible"
    preset="card"
    title="选择上传类型"
    style="width: 420px"
  >
    <NSpace vertical size="large">
      <div class="upload-dialog-desc">上传入口已统一，请先选择要导入的头像分组。</div>
      <NRadioGroup v-model:value="uploadTargetGender" name="uploadTargetGender">
        <NSpace vertical size="medium">
          <div
            class="upload-option"
            :class="{ 'upload-option--active': uploadTargetGender === 'male' }"
            @click="uploadTargetGender = 'male'"
          >
            <NRadio value="male">男生头像</NRadio>
          </div>
          <div
            class="upload-option"
            :class="{ 'upload-option--active': uploadTargetGender === 'female' }"
            @click="uploadTargetGender = 'female'"
          >
            <NRadio value="female">女生头像</NRadio>
          </div>
        </NSpace>
      </NRadioGroup>
      <NSpace justify="end">
        <NButton @click="uploadDialogVisible = false">取消</NButton>
        <NButton type="primary" :loading="saving" @click="confirmUploadTarget">继续上传</NButton>
      </NSpace>
    </NSpace>
  </NModal>

  <NModal
    v-model:show="nicknameUploadDialogVisible"
    preset="card"
    title="上传昵称素材"
    style="width: 520px"
  >
    <NSpace vertical size="large">
      <div class="upload-dialog-desc">
        上传入口已统一，请先选择要导入的昵称类型，再粘贴素材内容。
      </div>
      <NRadioGroup v-model:value="nicknameUploadTarget" name="nicknameUploadTarget">
        <div class="nickname-upload-grid">
          <div
            v-for="item in nicknameUploadTargets"
            :key="item.value"
            class="upload-option"
            :class="{ 'upload-option--active': nicknameUploadTarget === item.value }"
            @click="nicknameUploadTarget = item.value"
          >
            <NRadio :value="item.value">{{ item.label }}</NRadio>
          </div>
        </div>
      </NRadioGroup>
      <NInput
        v-model:value="nicknameUploadContent"
        type="textarea"
        :rows="6"
        :placeholder="nicknameUploadPlaceholder"
      />
      <NSpace justify="end">
        <NButton @click="closeNicknameUploadDialog">取消</NButton>
        <NButton type="primary" :loading="saving" @click="submitNicknameUpload">确认上传</NButton>
      </NSpace>
    </NSpace>
  </NModal>
</template>

<style scoped>
.toolbar-row {
  display: flex;
  justify-content: flex-end;
}

.summary-row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
  gap: 12px;
  margin-bottom: 16px;
}

.summary-item {
  border: 1px solid var(--n-border-color);
  border-radius: 8px;
  padding: 12px;
  background: var(--n-color);
}

.summary-label {
  color: var(--n-text-color-3);
  font-size: 12px;
  margin-bottom: 6px;
}

.summary-value {
  font-size: 22px;
  font-weight: 600;
  color: var(--n-text-color);
}

.panel-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.panel-title {
  font-size: 16px;
  font-weight: 600;
}

.panel-subtitle {
  font-size: 12px;
  color: var(--n-text-color-3);
  margin-top: 4px;
}

.hidden-file-input {
  display: none;
}

.avatar-item {
  position: relative;
  border: 1px solid var(--n-border-color);
  border-radius: 8px;
  padding: 8px;
  cursor: pointer;
  background: var(--n-color);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  transition: border-color 0.2s ease, box-shadow 0.2s ease, transform 0.2s ease;
}

.avatar-item:hover {
  border-color: #ff6a3d;
  box-shadow: 0 6px 18px rgba(255, 106, 61, 0.12);
}

.avatar-item--selected {
  border-color: #ff6a3d;
  background: rgba(255, 106, 61, 0.06);
  box-shadow: 0 0 0 2px rgba(255, 106, 61, 0.18);
}

.avatar-item--selected::after {
  content: '✓';
  position: absolute;
  top: 8px;
  right: 8px;
  width: 16px;
  height: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  background: #ff6a3d;
  box-shadow: 0 0 0 2px #fff;
  color: #fff;
  font-size: 12px;
  font-weight: 700;
  line-height: 1;
}

.avatar-item img {
  width: 104px;
  height: 104px;
  object-fit: cover;
  border-radius: 8px;
  background: #f5f5f5;
}

.nickname-layout {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
  gap: 16px;
}

.nickname-column {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.column-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.column-title {
  font-weight: 600;
}

.tag-panel {
  min-height: 84px;
  border: 1px dashed var(--n-border-color);
  border-radius: 8px;
  padding: 10px;
  background: var(--n-color);
}

.tag-flow {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.nickname-chip {
  border: 1px solid transparent;
  border-radius: 4px;
  padding: 4px 10px;
  font-size: 12px;
  line-height: 1.4;
  cursor: pointer;
  background: transparent;
  transition: border-color 0.2s ease, background-color 0.2s ease, color 0.2s ease,
    box-shadow 0.2s ease;
}

.nickname-chip--prefix {
  border-color: #8fd3a8;
  background: #effbf3;
  color: #27834f;
}

.nickname-chip--suffix {
  border-color: #9bc2ff;
  background: #eff5ff;
  color: #2b6edc;
}

.nickname-chip--selected {
  border-color: #ff6a3d;
  background: rgba(255, 106, 61, 0.1);
  color: #c7441a;
  box-shadow: 0 0 0 1px rgba(255, 106, 61, 0.12);
}

.nickname-upload-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}

.page-footer-hint {
  color: var(--n-text-color-3);
}

.upload-dialog-desc {
  color: var(--n-text-color-2);
  font-size: 13px;
  line-height: 1.5;
}

.upload-option {
  border: 1px solid var(--n-border-color);
  border-radius: 8px;
  padding: 12px 14px;
  cursor: pointer;
  transition: border-color 0.2s ease, background-color 0.2s ease;
}

.upload-option--active {
  border-color: #ff6a3d;
  background: rgba(255, 106, 61, 0.06);
}
</style>
