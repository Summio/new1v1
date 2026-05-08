<script setup>
import { h, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { NButton, NImage, NInput, NModal, NPopconfirm } from 'naive-ui'

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
    window.$message?.error(error?.message || '删除失败')
  }
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
    title: '操作',
    key: 'actions',
    width: 110,
    align: 'center',
    fixed: 'right',
    render(row) {
      return h(
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
      )
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
