<script setup>
import { h, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { NButton, NImage, NInput, NModal, NPopconfirm, NSelect, NSpace, NTag } from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate } from '@/utils'

defineOptions({ name: '动态管理' })

const route = useRoute()
const $table = ref(null)
const queryItems = ref({
  user_id: route.query.user_id ? String(route.query.user_id) : '',
})
const videoModalVisible = ref(false)
const currentVideo = ref({
  url: '',
  cover_url: '',
})
const pinStatusOptions = [
  { label: '全部', value: 'all' },
  { label: '已置顶', value: 'pinned' },
  { label: '普通', value: 'normal' },
]
const recommendStatusOptions = [
  { label: '全部', value: 'all' },
  { label: '有效推荐', value: 'recommended' },
  { label: '未推荐', value: 'not_recommended' },
  { label: '单条推荐', value: 'override_recommended' },
  { label: '单条取消推荐', value: 'override_cancelled' },
  { label: '跟随认证用户默认', value: 'default' },
]

onMounted(() => {
  $table.value?.handleSearch()
})

function openVideo(item) {
  currentVideo.value = {
    url: item?.url || '',
    cover_url: item?.cover_url || '',
  }
  videoModalVisible.value = true
}

async function handleDelete(row) {
  try {
    await api.deleteMoment({ id: row.id })
    window.$message?.success('删除成功')
    $table.value?.handleSearch()
  } catch (error) {
    $table.value?.handleSearch()
  }
}

async function runMomentAction(action, row, successMessage, fallbackMessage) {
  try {
    await action({ id: row.id })
    window.$message?.success(successMessage)
    $table.value?.handleSearch()
  } catch (error) {
    if (error?.code === 400) {
      $table.value?.handleSearch()
      return
    }
    window.$message?.error(error?.message || fallbackMessage)
  }
}

function handlePin(row) {
  return runMomentAction(api.pinMoment, row, '置顶成功', '置顶失败')
}

function handleUnpin(row) {
  return runMomentAction(api.unpinMoment, row, '取消置顶成功', '取消置顶失败')
}

function handleRecommend(row) {
  return runMomentAction(api.recommendMoment, row, '推荐成功', '推荐失败')
}

function handleUnrecommend(row) {
  return runMomentAction(api.unrecommendMoment, row, '取消推荐成功', '取消推荐失败')
}

function handleClearRecommendOverride(row) {
  return runMomentAction(api.clearMomentRecommendOverride, row, '恢复默认成功', '恢复默认失败')
}

function recommendTagType(row) {
  if (row.recommend_override === true) return 'success'
  if (row.recommend_override === false) return 'warning'
  if (row.author_is_recommended) return 'info'
  return 'default'
}

function recommendStatusLabel(row) {
  if (row.recommend_override === true) return '单条推荐'
  if (row.recommend_override === false) return '单条取消推荐'
  if (row.author_is_recommended) return '推荐认证用户默认推荐'
  return row.recommend_status_label || '未推荐'
}

const columns = [
  { title: '动态ID', key: 'id', width: 90, align: 'center' },
  {
    title: '用户',
    key: 'user',
    width: 240,
    render(row) {
      return h('div', { class: 'user-cell' }, [
        row.avatar
          ? h(NImage, {
              src: row.avatar,
              width: 42,
              height: 42,
              objectFit: 'cover',
              previewDisabled: false,
              imgProps: { class: 'avatar-thumb', alt: 'avatar' },
            })
          : h('div', { class: 'avatar-placeholder' }, '无'),
        h('div', { class: 'user-meta' }, [
          h('div', {}, `ID: ${row.user_id}`),
          h('div', { class: 'sub' }, `${row.nickname || '-'} / ${row.phone || '-'}`),
        ]),
      ])
    },
  },
  {
    title: '内容',
    key: 'content',
    minWidth: 280,
    render(row) {
      return row.content || '-'
    },
  },
  {
    title: '媒体',
    key: 'media_count',
    width: 260,
    render(row) {
      const mediaList = Array.isArray(row.media_list) ? row.media_list : []
      if (!mediaList.length) return '-'
      return h(
        'div',
        { class: 'media-inline-list' },
        mediaList.map((item) => {
          if (Number(item.media_type) === 2) {
            return h(
              'div',
              {
                key: item.id,
                class: 'media-inline-thumb media-video-thumb',
                role: 'button',
                tabindex: 0,
                style: {
                  width: '54px',
                  height: '54px',
                  minWidth: '54px',
                  minHeight: '54px',
                  maxWidth: '54px',
                  maxHeight: '54px',
                  flex: '0 0 54px',
                  boxSizing: 'border-box',
                },
                onClick: () => openVideo(item),
                onKeydown: (event) => {
                  if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault()
                    openVideo(item)
                  }
                },
              },
              [
                item.cover_url
                  ? h('img', {
                      src: item.cover_url,
                      alt: 'video-cover',
                      style: {
                        width: '100%',
                        height: '100%',
                        display: 'block',
                        objectFit: 'cover',
                      },
                    })
                  : h(
                      'span',
                      {
                        class: 'video-empty',
                        style: {
                          width: '100%',
                          height: '100%',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                        },
                      },
                      '视频'
                    ),
                h('span', { class: 'play-mark' }, '▶'),
              ]
            )
          }
          return h(NImage, {
            key: item.id,
            src: item.url,
            width: 54,
            height: 54,
            objectFit: 'cover',
            previewDisabled: false,
            imgProps: {
              class: 'media-inline-img',
              alt: 'moment-media',
            },
          })
        })
      )
    },
  },
  {
    title: '发布时间',
    key: 'created_at',
    width: 170,
    align: 'center',
    render(row) {
      return row.created_at ? formatDate(row.created_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '置顶',
    key: 'is_pinned',
    width: 90,
    align: 'center',
    render(row) {
      return h(
        NTag,
        { type: row.is_pinned ? 'success' : 'default', size: 'small' },
        { default: () => (row.is_pinned ? '已置顶' : '普通') }
      )
    },
  },
  {
    title: '推荐状态',
    key: 'recommend_status_label',
    width: 150,
    align: 'center',
    render(row) {
      return h(
        NTag,
        { type: recommendTagType(row), size: 'small' },
        { default: () => recommendStatusLabel(row) }
      )
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 280,
    align: 'center',
    fixed: 'right',
    render(row) {
      return h(NSpace, { size: 6, justify: 'center' }, () => [
        row.is_pinned
          ? h(
              NButton,
              { size: 'small', secondary: true, onClick: () => handleUnpin(row) },
              { default: () => '取消置顶' }
            )
          : h(
              NButton,
              { size: 'small', type: 'primary', secondary: true, onClick: () => handlePin(row) },
              { default: () => '置顶' }
            ),
        row.is_recommended
          ? h(
              NButton,
              {
                size: 'small',
                type: 'warning',
                secondary: true,
                onClick: () => handleUnrecommend(row),
              },
              { default: () => '取消推荐' }
            )
          : h(
              NButton,
              {
                size: 'small',
                type: 'success',
                secondary: true,
                onClick: () => handleRecommend(row),
              },
              { default: () => '推荐' }
            ),
        row.recommend_override !== null && row.recommend_override !== undefined
          ? h(
              NButton,
              { size: 'small', secondary: true, onClick: () => handleClearRecommendOverride(row) },
              { default: () => '恢复默认' }
            )
          : null,
        h(
          NPopconfirm,
          {
            onPositiveClick: () => handleDelete(row),
          },
          {
            trigger: () =>
              h(
                NButton,
                { size: 'small', type: 'error', secondary: true },
                { default: () => '删除' }
              ),
            default: () => '确认删除这条动态？',
          }
        ),
      ])
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="动态管理">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="api.getMomentList"
      :scroll-x="1150"
    >
      <template #queryBar>
        <QueryBarItem label="用户ID" :label-width="55">
          <NInput
            v-model:value="queryItems.user_id"
            clearable
            placeholder="请输入用户ID"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="关键词" :label-width="55">
          <NInput
            v-model:value="queryItems.keyword"
            clearable
            placeholder="昵称/手机号/内容"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="置顶状态" :label-width="70">
          <NSelect
            v-model:value="queryItems.pin_status"
            clearable
            :options="pinStatusOptions"
            placeholder="全部"
            style="width: 120px"
          />
        </QueryBarItem>
        <QueryBarItem label="推荐状态" :label-width="70">
          <NSelect
            v-model:value="queryItems.recommend_status"
            clearable
            :options="recommendStatusOptions"
            placeholder="全部"
            style="width: 170px"
          />
        </QueryBarItem>
      </template>
    </CrudTable>

    <NModal v-model:show="videoModalVisible" preset="card" title="播放视频" style="width: 760px">
      <video
        v-if="currentVideo.url"
        class="video-player"
        :src="currentVideo.url"
        :poster="currentVideo.cover_url || undefined"
        controls
        autoplay
        playsinline
      />
    </NModal>
  </CommonPage>
</template>

<style scoped>
.user-cell {
  display: flex;
  align-items: center;
  gap: 10px;
}

.avatar-thumb,
.avatar-placeholder {
  width: 42px;
  height: 42px;
  border-radius: 8px;
  border: 1px solid #eceff5;
  flex: 0 0 auto;
}

.avatar-thumb {
  object-fit: cover;
}

.avatar-placeholder {
  display: flex;
  align-items: center;
  justify-content: center;
  color: #8b8f99;
  background: #f7f8fb;
  font-size: 12px;
}

.user-meta {
  min-width: 0;
}

.sub {
  color: #8b8f99;
  font-size: 12px;
  margin-top: 2px;
}

.media-inline-list {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}

.media-inline-img,
.media-inline-thumb {
  width: 54px !important;
  height: 54px !important;
  min-width: 54px;
  min-height: 54px;
  max-width: 54px;
  max-height: 54px;
  border-radius: 8px;
  border: 1px solid #eceff5;
  object-fit: cover;
  box-sizing: border-box;
  flex: 0 0 54px;
}

.media-inline-thumb {
  position: relative;
  overflow: hidden;
  padding: 0;
  background: #f7f8fb;
  color: #8b8f99;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.media-inline-thumb img {
  width: 100% !important;
  height: 100% !important;
  object-fit: cover;
  display: block;
}

.video-empty {
  font-size: 12px;
}

.play-mark {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  background: rgb(0 0 0 / 28%);
  font-size: 18px;
  line-height: 1;
}

.video-player {
  width: 100%;
  max-height: 70vh;
  border-radius: 8px;
  background: #000;
}
</style>
