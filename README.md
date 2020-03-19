Development Model
=================

When working on this project, the following method of
development should be followed to prevent dependent
projects from breaking. Of course, over time we may
adjust these steps to optimize the process or remove
redundancies.

Obtaining the Source
--------------------

The official repository is currently on Fermilab's Redmine
installation. To check it out:

    $ git clone ssh://p-acnetd@cdcvs.fnal.gov/cvs/projects/acnetd-dart
    $ cd acnetd-dart

At this point, your working directory is on the `master`
branch. **No development should be done directly on the
`master` branch!** Right now we keep the `master` branch in
sync with the current release branch, `v0.x`. So the next
step is to check it out, too:

     $ git checkout v0.x
 
Projects that use this Dart module can track the `v0.x`
branch to automatically get updates. This means the HEAD
of this branch must be well tested and usable. For
development, you should make a local branch. This author
typically names it `devel`:

    $ git checkout -b devel

On this branch, as many intermediate commits can be made,
as necessary. **Never push the `devel` branch back to the
official repo!**

Merging Your Changes
--------------------

Once you have completed, tested, and debugged your changes,
it's time to incorporate them into the official repo. We
do this by merging the `devel` branch into the `v0.x` branch.
So switch back to the `v0.x` branch:

    $ git checkout v0.x

Before we merge `devel` we have to make sure someone else
hasn't already changed the `v0.x` branch:

    $ git pull origin v0.x

If `git` reports it's up-to-date, you can skip the next step
and proceed to merge your changes. On the other hand, if
`git` pulled in changes, you have a little work ahead:

    $ git checkout devel
    $ git merge v0.x            # or 'git rebase v0.x'

You'll need to fix whatever conflicts occurred and then
test and debug your changes again. Once that's complete,
start at the top of this section.

So now you're ready to merge your changes to `v0.x`. We
want `v0.x` (and `master`) to be made of "merge commits"
so to do this, run:

    $ git checkout v0.x
    $ git merge --no-ff devel

You'll be prompted for a commit message for the merge. Please
use this opportunity to summarize all the changes being merged.

You need to also tag this commit with the official (i.e. next)
release number. You can see the list of tags with:

    $ git tag -l

You should only increment the minor version; changing the
major version requires making a new version branch, etc.
Assuming the project has versions v0.1 and v0.2, we would
register a new tag as

    $ git tag v0.3

Finally, we need to push these changes to the official repo:

    $ git checkout master
    $ git merge v0.x              # keep master in sync
    $ git push origin master
    $ git push origin v0.x
    $ git push --tags