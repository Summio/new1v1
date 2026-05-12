<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import {
  NButton,
  NCard,
  NCheckbox,
  NEmpty,
  NGrid,
  NGridItem,
  NInput,
  NScrollbar,
  NSpace,
  NTabPane,
  NTabs,
  NTag,
  useMessage,
} from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import { renderIcon } from '@/utils'
import api from '@/api'

defineOptions({ name: '初始资料管理' })

const message = useMessage()
const loading = ref(false)
const saving = ref(false)
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
  nicknameDrafts: {
    male: { prefixes: '', suffixes: '' },
    female: { prefixes: '', suffixes: '' },
  },
  selectedAvatars: {
    male: [],
    female: [],
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

async function removeAvatar(gender, url) {
  state.avatarPool[gender] = state.avatarPool[gender].filter((item) => item !== url)
  state.selectedAvatars[gender] = state.selectedAvatars[gender].filter((item) => item !== url)
  await saveAvatarPool()
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

async function removeNickname(gender, section, value) {
  state.nicknamePool[gender][section] = state.nicknamePool[gender][section].filter(
    (item) => item !== value
  )
  await saveNicknamePool()
}

async function importNickname(gender, section) {
  const content = state.nicknameDrafts[gender][section]
  if (!content.trim()) {
    message.warning('请先输入素材')
    return
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
    state.nicknameDrafts[gender][section] = ''
    await loadConfig()
  } catch (error) {
    message.error(error?.message || '导入失败')
    console.error(error)
  } finally {
    saving.value = false
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
          <NCard v-for="gender in ['male', 'female']" :key="gender" size="small" :bordered="false">
            <template #header>
              <div class="panel-header">
                <div>
                  <div class="panel-title">{{ genderMeta[gender].label }}头像</div>
                  <div class="panel-subtitle">批量上传、按选中删除、直接保存分组结果</div>
                </div>
                <NSpace>
                  <NButton :loading="saving" type="primary" @click="openAvatarPicker(gender)">
                    <template #icon>
                      <component :is="renderIcon('material-symbols:upload')" />
                    </template>
                    批量上传
                  </NButton>
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
                  <NButton :loading="saving" @click="saveAvatarPool">
                    <template #icon>
                      <component :is="renderIcon('material-symbols:save')" />
                    </template>
                    保存
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
                  <div class="avatar-item">
                    <NCheckbox
                      :checked="state.selectedAvatars[gender].includes(url)"
                      @update:checked="toggleAvatar(gender, url)"
                    />
                    <img :src="url" alt="头像素材" />
                    <NButton
                      size="tiny"
                      tertiary
                      type="error"
                      @click.stop="removeAvatar(gender, url)"
                    >
                      <template #icon>
                        <component
                          :is="renderIcon('material-symbols:delete-outline', { size: 14 })"
                        />
                      </template>
                      删除
                    </NButton>
                  </div>
                </NGridItem>
              </NGrid>
            </NScrollbar>
          </NCard>
        </NSpace>
      </NTabPane>

      <NTabPane name="nickname" tab="昵称池">
        <NSpace vertical size="large">
          <NCard v-for="gender in ['male', 'female']" :key="gender" size="small" :bordered="false">
            <template #header>
              <div class="panel-header">
                <div>
                  <div class="panel-title">{{ genderMeta[gender].label }}昵称</div>
                  <div class="panel-subtitle">前缀和后缀分开维护，批量粘贴后自动去重</div>
                </div>
                <NButton :loading="saving" @click="saveNicknamePool">
                  <template #icon>
                    <component :is="renderIcon('material-symbols:save')" />
                  </template>
                  保存
                </NButton>
              </div>
            </template>

            <div class="nickname-layout">
              <div class="nickname-column">
                <div class="column-title">前缀列表</div>
                <div class="tag-panel">
                  <NEmpty
                    v-if="!state.nicknamePool[gender].prefixes.length"
                    description="暂无素材"
                  />
                  <div v-else class="tag-flow">
                    <NTag
                      v-for="item in state.nicknamePool[gender].prefixes"
                      :key="item"
                      closable
                      :round="false"
                      size="small"
                      type="success"
                      @close="removeNickname(gender, 'prefixes', item)"
                    >
                      {{ item }}
                    </NTag>
                  </div>
                </div>
                <NInput
                  v-model:value="state.nicknameDrafts[gender].prefixes"
                  type="textarea"
                  :rows="4"
                  placeholder="用、隔开多个前缀，例如：阳光、清爽、温柔"
                />
                <NSpace justify="end">
                  <NButton
                    :loading="saving"
                    type="primary"
                    @click="importNickname(gender, 'prefixes')"
                  >
                    批量新增前缀
                  </NButton>
                </NSpace>
              </div>

              <div class="nickname-column">
                <div class="column-title">后缀列表</div>
                <div class="tag-panel">
                  <NEmpty
                    v-if="!state.nicknamePool[gender].suffixes.length"
                    description="暂无素材"
                  />
                  <div v-else class="tag-flow">
                    <NTag
                      v-for="item in state.nicknamePool[gender].suffixes"
                      :key="item"
                      closable
                      :round="false"
                      size="small"
                      type="info"
                      @close="removeNickname(gender, 'suffixes', item)"
                    >
                      {{ item }}
                    </NTag>
                  </div>
                </div>
                <NInput
                  v-model:value="state.nicknameDrafts[gender].suffixes"
                  type="textarea"
                  :rows="4"
                  placeholder="用、隔开多个后缀，例如：少年、先生、小哥"
                />
                <NSpace justify="end">
                  <NButton
                    :loading="saving"
                    type="primary"
                    @click="importNickname(gender, 'suffixes')"
                  >
                    批量新增后缀
                  </NButton>
                </NSpace>
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
</template>

<style scoped>
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

.page-footer-hint {
  color: var(--n-text-color-3);
}
</style>
