// GitHub Actions injects its Octokit client. This module has no credentials
// or network access of its own; the pure planner is exercised with test data.
export async function planBranchCleanup({branches, openPrs, closedPrs,
  defaultBranch, repoFullName, obsoleteHeads = []}, compare) {
  const main = branches.find(b => b.name === defaultBranch);
  if (!main) throw new Error('Default branch missing; refusing cleanup');
  const localHead = p => p.head?.repo?.full_name === repoFullName;
  const active = new Set(openPrs.filter(localHead).map(p => p.head.ref));
  const mergedHeads = new Set(closedPrs.filter(p => localHead(p) &&
    p.merged_at && p.base?.ref === defaultBranch).map(p => `${p.head.ref}:${p.head.sha}`));
  const closedHeads = new Set(closedPrs.filter(localHead)
    .map(p => `${p.head.ref}:${p.head.sha}:${p.number}`));
  const obsolete = new Map(obsoleteHeads.map(e => [e.branch, e]));
  const result = [];
  for (const branch of branches) {
    let reason = null;
    if (branch.name === defaultBranch || branch.protected || active.has(branch.name)) {
      result.push({branch, remove: false, reason: 'default, protected or active PR'});
      continue;
    }
    const key = `${branch.name}:${branch.commit.sha}`;
    if (mergedHeads.has(key)) reason = 'exact head of PR merged into default branch';
    const abandoned = obsolete.get(branch.name);
    if (!reason && abandoned?.sha === branch.commit.sha &&
        closedHeads.has(`${key}:${abandoned.pr}`)) reason = abandoned.reason;
    if (!reason) {
      try {
        const status = await compare(branch.commit.sha, main.commit.sha);
        if (status.status === 'identical' ||
            (status.status === 'ahead' && status.behind_by === 0)) {
          reason = 'commit reachable from default branch';
        }
      } catch {
        // Failure to prove completion keeps the branch.
      }
    }
    result.push({branch, remove: reason !== null, reason: reason ?? 'unmerged or changed head'});
  }
  return result;
}

export async function runBranchHygiene({github, context, core, obsoleteHeads}) {
  const {owner, repo} = context.repo;
  const repository = (await github.rest.repos.get({owner, repo})).data;
  const defaultBranch = repository.default_branch;
  const branches = await github.paginate(github.rest.repos.listBranches, {owner, repo, per_page: 100});
  const openPrs = await github.paginate(github.rest.pulls.list, {owner, repo, state: 'open', per_page: 100});
  const closedPrs = await github.paginate(github.rest.pulls.list, {owner, repo, state: 'closed', per_page: 100});
  const plan = await planBranchCleanup({branches, openPrs, closedPrs,
    defaultBranch, repoFullName: repository.full_name, obsoleteHeads}, async (head, main) =>
    (await github.rest.repos.compareCommitsWithBasehead({owner, repo, basehead: `${head}...${main}`})).data);
  const deleted = [], kept = [];
  for (const item of plan) {
    const branch = item.branch;
    if (!item.remove) { kept.push(`${branch.name}: ${item.reason}`); continue; }
    try {
      // Re-read immediately before removal. A newly opened PR or a pushed
      // commit changes the decision; no deletion occurs in that case.
      const active = await github.paginate(github.rest.pulls.list,
        {owner, repo, state: 'open', head: `${owner}:${branch.name}`, per_page: 100});
      const current = (await github.rest.git.getRef({owner, repo, ref: `heads/${branch.name}`})).data;
      if (active.length || current.object.sha !== branch.commit.sha) {
        kept.push(`${branch.name}: changed during cleanup`); continue;
      }
      await github.rest.git.deleteRef({owner, repo, ref: `heads/${branch.name}`});
      deleted.push(`${branch.name} @ ${branch.commit.sha}: ${item.reason}`);
    } catch (error) {
      kept.push(`${branch.name}: deletion unavailable`);
      core.warning(`Keeping ${branch.name}: ${error.message}`);
    }
  }
  core.summary.addHeading('Repository branch hygiene')
    .addRaw(`Deleted: ${deleted.length}\n\n`).addCodeBlock(deleted.join('\n') || '(none)')
    .addRaw(`\nKept: ${kept.length}\n\n`).addCodeBlock(kept.join('\n') || '(none)');
  await core.summary.write();
}
