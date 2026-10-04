import {test} from 'node:test';
import assert from 'node:assert/strict';
import {planBranchCleanup, runBranchHygiene} from './repository-branch-hygiene.mjs';

const repoFullName = 'owner/repo';
const branch = (name, sha = 'old', protectedFlag = false) =>
  ({name, commit: {sha}, protected: protectedFlag});
const pr = (ref, sha, extra = {}) => ({number: 10,
  head: {ref, sha, repo: {full_name: repoFullName}}, base: {ref: 'main'}, ...extra});
const plan = (extra, compare = async () => ({status: 'diverged', behind_by: 1})) =>
  planBranchCleanup({branches: [branch('main', 'main'), branch('work')],
    openPrs: [], closedPrs: [], defaultBranch: 'main', repoFullName, ...extra}, compare);

test('open PR protects an otherwise merged or explicitly obsolete branch', async () => {
  const rows = await plan({openPrs: [pr('work', 'old')],
    closedPrs: [pr('work', 'old', {merged_at: 'date'})],
    obsoleteHeads: [{branch: 'work', sha: 'old', pr: 10, reason: 'obsolete'}]});
  assert.equal(rows[1].remove, false);
});
test('protected and default branches are preserved', async () => {
  const rows = await plan({branches: [branch('main'), branch('work', 'old', true)]},
    async () => ({status: 'identical'}));
  assert.ok(rows.every(r => !r.remove));
});
test('exact head of a squash merged PR is removable', async () => {
  const rows = await plan({closedPrs: [pr('work', 'old', {merged_at: 'date'})]});
  assert.equal(rows[1].remove, true);
});
test('a new commit or a PR merged into another base preserves branch', async () => {
  const newer = await plan({closedPrs: [pr('work', 'earlier', {merged_at: 'date'})]});
  const other = await plan({closedPrs: [pr('work', 'old', {merged_at: 'date', base: {ref: 'stage'}})]});
  assert.equal(newer[1].remove, false); assert.equal(other[1].remove, false);
});
test('abandoned branch requires matching SHA and a closed local PR', async () => {
  const config = {obsoleteHeads: [{branch: 'work', sha: 'old', pr: 10, reason: 'replaced'}]};
  assert.equal((await plan(config))[1].remove, false);
  assert.equal((await plan({...config, closedPrs: [pr('work', 'old')]}))[1].remove, true);
});
test('only proven ancestors are removed and comparison errors preserve work', async () => {
  assert.equal((await plan({}, async () => ({status: 'ahead', behind_by: 0})))[1].remove, true);
  assert.equal((await plan({}, async () => {throw new Error('unavailable');}))[1].remove, false);
});
test('a fork PR is not evidence to delete a local branch', async () => {
  const fork = pr('work', 'old', {merged_at: 'date'});
  fork.head.repo.full_name = 'someone/fork';
  assert.equal((await plan({closedPrs: [fork]}))[1].remove, false);
});
test('missing main refuses cleanup', async () => {
  await assert.rejects(() => plan({branches: [branch('work')]}), /Default branch missing/);
});
test('runner rechecks a changed head before mutation', async () => {
  let deletes = 0;
  const repos = {get: async () => ({data: {default_branch: 'main', full_name: repoFullName}}),
    listBranches: 'branches', compareCommitsWithBasehead: async () => ({data: {status: 'identical'}})};
  const github = {rest: {repos, pulls: {list: 'pulls'}, git: {
    getRef: async () => ({data: {object: {sha: 'new'}}}),
    deleteRef: async () => {deletes++;},
  }}, paginate: async (method, args) => method === 'branches'
    ? [branch('main', 'main'), branch('work')]
    : []};
  const summary = {addHeading(){return this;}, addRaw(){return this;},
    addCodeBlock(){return this;}, async write(){}};
  await runBranchHygiene({github, context: {repo: {owner: 'owner', repo: 'repo'}},
    core: {summary, warning(){}}, obsoleteHeads: []});
  assert.equal(deletes, 0);
});
