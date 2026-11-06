#!/bin/zsh
# Publishes the download page (site/) to GitHub Pages, from the releases repository's main branch,
# at https://jyun1004.github.io/Minical-releases/. The repository keeps its README and releases.
#
#   scripts/publish-site.sh
#
# The first time, turn Pages on (main branch, root):
#   gh api -X POST repos/jyun1004/Minical-releases/pages -f "source[branch]=main" -f "source[path]=/"
set -euo pipefail
cd "${0:a:h}/.."
repo="${REPO:-jyun1004/Minical-releases}"
work="build/site-repo"
rm -rf "$work"
gh repo clone "$repo" "$work" -- --quiet --depth 1
rsync -a --delete --exclude .git --exclude .nojekyll site/ "$work/"
touch "$work/.nojekyll"
cd "$work"
git add -A
if git diff --cached --quiet; then
    print "The page is already up to date."
    exit 0
fi
git commit --quiet -m "Update the download page"
git push --quiet
print "Published: https://${repo%%/*}.github.io/${repo#*/}/"
