export const scenarios = [
  {
    id: 'public_nav',
    url: 'https://example.com',
    timeoutMs: 90000,
    expectTitle: 'Example Domain',
    expectTextIncludes: 'documentation examples',
  },
  {
    id: 'youtube_light',
    url: 'https://www.youtube.com',
    timeoutMs: 90000,
    query: 'open source',
    minTitles: 3,
    bestEffort: true,
  },
  {
    id: 'explore',
    url: 'https://news.ycombinator.com',
    timeoutMs: 90000,
    minItems: 12,
  },
  {
    id: 'explore2',
    url: 'https://react.dev/learn',
    timeoutMs: 90000,
    minItems: 12,
  },
  {
    id: 'auth_roundtrip',
    timeoutMs: 90000,
  },
  {
    id: 'spa_task',
    timeoutMs: 90000,
    path: '/app',
    minItems: 5,
  },
]

export function getScenario(id) {
  return scenarios.find((s) => s.id === id) ?? null
}
