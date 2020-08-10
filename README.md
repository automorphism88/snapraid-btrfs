# snapraid-btrfs

`snapraid-btrfs` is a script for using [SnapRAID](http://www.snapraid.it/) with
data drives which are formatted with btrfs. It allows operations such as
`snapraid sync` or `snapraid scrub` which do not write to the data drives to be
done using read-only snapshots, and when running SnapRAID operations which do
write to the data drives (i.e., `snapraid fix` and `snapraid touch`) it creates
before and after snapshots. It aims to be a transparent wrapper around the
`snapraid` command, allowing you to replace, e.g., `snapraid sync` with
`snapraid-btrfs sync`, and works by creating a temporary SnapRAID configuration
file where the data paths are replaced with those of corresponding read-only
snapshots, then running `snapraid` using the temporary configuration file.

Options appearing before the command (e.g., `sync` or `scrub`) control the
behavior of `snapraid-btrfs`, while options appearing after the command are
passed through to `snapraid`, with the exception of `-c`/`--conf`, which is
reserved for use by `snapraid-btrfs` to point `snapraid` to its temporary
configuration file, and which can instead be specified as a `snapraid-btrfs`
option, before the command, so that it can be processed by `snapraid-btrfs`
when creating the temporary SnapRAID config file. For example,
`snapraid-btrfs -c /foo/snapraid.conf sync -v` would run
`snapraid sync -c /tmp/example -v`, where `/tmp/example` was generated using
`/foo/snapraid.conf` instead of `/etc/snapraid.conf`. `snapraid-btrfs` also
implements additional commands, such as `cleanup`, for managing its snapshots.

## Setup instructions

To start using `snapraid-btrfs`, you need to set up
[snapper](http://snapper.io/) configurations for each data drive that you want
`snapraid-btrfs` to make snapshots of. At runtime, `snapraid-btrfs` will follow
the following procedure to find snapper configs:

1. Look at filenames in `/etc/snapper/configs` (or an alternate directory
specified by setting the `SNAPPER_CONFIG_DIR` environment variable) to get the
names of snapper configs. This directory should be readable by the user running
`snapraid-btrfs`, but the files inside it need not be.
2. For each config found, attempt to read the `SUBVOLUME` variable using
`snapper get-config`. If this command fails (generally because the user is not
included in `ALLOW_USERS` or `ALLOW_GROUPS`), skip the config.
3. If successful in reading `SUBVOLUME`, attempt to find a matching data drive
in the SnapRAID configuration file.

`snapraid-btrfs` will ignore any data drives which it does not find
corresponding snapper configs for (in other words, the live filesystem will be
used for all operations and no snapshots will be created. Just like SnapRAID,
`snapraid-btrfs` will use `/etc/snapraid.conf` by default, but another
configuration file can be specified using the `-c`/`--conf` option, or by
setting the `SNAPRAID_CONFIG_FILE` environment variable.

All files on the data drives which are not excluded by the SnapRAID
configuration file must be in the same subvolume. **If any of the SnapRAID
"content" files are stored on data drives, create a dedicated subvolume for
them so that they are not snapshotted.** It is also recommended that you add
the line `exclude /.snapshots/` to your SnapRAID configuration file, so that if
you ever run `snapraid sync` instead of `snapraid-btrfs sync`, SnapRAID will
not try to sync both the live filesystem and the read-only snapshots, causing
it to run out of parity space.

See the FAQ below for more details. To verify that snapper has been set up
correctly, you can use the `snapraid-btrfs ls` command, which will run
`snapper ls` for all of the snapper configurations that it recognizes as
matching data drives in your SnapRAID configuration file. If `snapraid-btrfs`
does not find all of the snapper configs you were expecting, try using the
`--verbose` option. Once you are satisfied that `snapraid-btrfs` has found all
of your configs, you are ready to run your first `snapraid-btrfs sync` which
will, by default, create new snapshots and use them for the sync. For more
details on using `snapraid-btrfs`, see the output of `snapraid-btrfs --help`.

## Dependencies

- [SnapRAID](http://www.snapraid.it/)
- [snapper](http://snapper.io/)
- [bash](https://www.gnu.org/software/bash/) (version 4.1+)
- awk, sed, grep, and coreutils (should all be installed by default in any
  modern distro, and any POSIX-compliant versions should work, as nonportable
  features are avoided)

All dependencies are checked on startup, and if any of them are not found,
`snapraid-btrfs` will display an error message and exit. Note that by default,
`snapraid-btrfs` will search for `snapraid` and `snapper` in the user's `PATH`,
but alternatively, the `--snapper-path` and/or `--snapraid-path` command line
options can be specified.

`#!/bin/bash` is used as the shebang (as the `#!/usr/bin/env bash` trick has
disadvantages), so if a compatible version of bash cannot be found there, one
of the following workarounds must be used:

- Create a symlink. This is generally already done on distros that have done
  the `/usr` merge and install bash in `/usr/bin` instead of `/bin`.
- Run `snapraid-btrfs` using `/path/to/right/bash /path/to/snapraid-btrfs`,
  possibly by creating a wrapper script or shell alias
- Manually edit the first line of the script to point to the correct location

## FAQ

### Q: Why use snapraid-btrfs?
A: A major disadvantage of SnapRAID is that the parity files are not updated in
realtime. This not only means that new files are not protected until after
running `snapraid sync`, but also creates a form of "write hole" where if files
are modified or deleted, some protection of other files which share the same
parity block(s) is lost until another sync is completed, since if other files
need to be restored using the `snapraid fix` command, the deleted or modified
files will not be available, just as if the disk had failed, or developed a bad
sector. This problem can be mitigated by adding additional parities, since
SnapRAID permits up to six, or worked around by temporarily moving files into a
directory that is excluded in your SnapRAID config file, then completing a sync
to remove them from the parity before deleting them. However, this problem is a
textbook use case for btrfs snapshots.

By using read-only snapshots when we do a `snapraid sync`, we ensure that if we
modify or delete files during or after the sync, we can always restore the
array to the state it was in at the time the read-only snapshots were created,
so long as the snapshots are not deleted until another sync is completed with
new snapshots. This use case for btrfs snapshots is similar to using
`btrfs send/receive` to back up a live filesystem, where the use of read-only
snapshots guarantees the consistency of the result, while using `dd` would
require that the entire filesystem be mounted read-only to prevent corruption
caused by writes to the live filesystem during the backup.

### Q: Are all SnapRAID commands supported?
A: Only the ones which either read from or write to the data drives, since for
the others (e.g. `snapraid smart`), there is no benefit to using btrfs
snapshots. Note that `snapraid-btrfs` does not interfere with the ability to
invoke SnapRAID directly, allowing you to use these commands, or any other
SnapRAID command, with `snapraid-btrfs` temporarily disabled.

### Q: Do I need to use btrfs for all of the data drives?
A: No. Any drives that don't have a corresponding snapper configuration will be
ignored (meaning that the live filesystem will be used). This allows you to
format data drives with any filesystem supported by SnapRAID. However, the
protection offered by `snapraid-btrfs` will not be available for writes made to
any data drives that it does not manage.

### Q: What about the parity drives?
A: Since the parity files are (or, at least, should be) only written to during
`snapraid sync` operations, there is no need to snapshot them, as the parity
files will always correspond with the read-only snapshots they were created
from. If a sync is interrupted, different sets of snapshots will correspond
with different portions of the parity file(s), and both sets of snapshots
should be retained until a sync is completed, at which point all previous
snapshots can be safely cleaned up. A snapper userdata key is used to keep
track of whether a `snapraid sync` run on a set of snapshots completes
successfully (i.e., returns exit status 0) to ensure that
`snapraid-btrfs cleanup` can handle this situation properly.

It is recommended that you use ext4 for the parity drives, since the metadata
overhead is extremely small with the right mkfs settings (minimum possible
number of inodes, minimum journal size (or journaling disabled), and no space
reserved for root - see `man mke2fs` for more details), and because for the
parity drives, there is no real use for any of the features which btrfs
offers over ext4.

### Q: What about the SnapRAID "content" files?
A: Just like the parity files, these do not need to be snapshotted. If they are
stored on the data drives, they should be in a dedicated subvolume, separate
from the one where the data is stored.

### Q: What about the space consumed by the snapshots?
A: Running out of parity space is not an issue (at least, no more of an issue
than it is without the use of snapshots), since only one snapshot at a time is
used for a sync. You may temporarily run out of space on the data drives if you
replace existing files with new data, but you can always free up that space by
doing a new sync with new snapshots, and then deleting the old snapshots using
the `snapraid-btrfs cleanup` command.

In the worst case (which occurs when the array is almost full), as changes are
made to the array, the use of snapshots will double the time spent syncing the
changes into the parity, but the capacity of the array will not be affected.
To the extent you do not have extra space to spare, after deleting files, you
will have to sync them out of the parity before the space they occupy can be
freed using `snapraid-btrfs cleanup`, allowing you to add new files, following
which a second sync operation would be required to add them to the parity.

If you have enough space to spare, you can add the new data before the initial
sync instead of waiting until after the post-sync cleanup, in which case the
speed of syncing is no different than without `snapraid-btrfs`. And you can
reduce the amount of free space required to avoid the worst-case behavior by
syncing more frequently, before the live filesystem diverges too much from the
snapshots, and always running `snapraid-btrfs cleanup` after each successful
sync.

This is an unavoidable limitation of the protection provided by
`snapraid-btrfs`, and the same price would be paid for any solution to the
problem `snapraid-btrfs` aims to solve - e.g. moving files to a directory which
is excluded in the SnapRAID config file before deleting them. To preserve the
ability to restore the array to the state it was in at the time of the last
sync even if files are modified or deleted, those files must be saved somewhere
until the parity has been brought up to date.

### Q: Does snapraid-btrfs need to be run as root?
A: No, and it is recommended that you do not do so, just as you should not run
SnapRAID as root.

### Q: How do I make sure my user (or group) has the necessary permissions?
A: Assuming you already have a working SnapRAID configuration, you just need to
configure snapper correctly. See "How do I set up snapper for use with
`snapraid-btrfs`?" below.

### Q: How do I configure snapper for use with snapraid-btrfs?
A: Create a snapper configuration for each data drive you want to use
`snapraid-btrfs` for, and make sure to set `SYNC_ACL=yes` in addition to
`ALLOW_USERS` or `ALLOW_GROUPS` for the user(s) and/or group(s) which will run
snapraid-btrfs in your snapper configurations. You may wish to make a snapper
template with the options you want to use for your SnapRAID drive
configurations and set these variables at that level. For further details, see
the snapper documentation.

### Q: What about my snapraid.conf file? Do I need to do anything there?
A: `snapraid-btrfs` is designed to work with your existing SnapRAID
configuration without requiring further changes. However, you may wish to add
the line `exclude /.snapshots/` to your config file. If you ever plan to sync
your SnapRAID configuration without using `snapraid-btrfs` (or disable it for
specific drives using the command-line options), SnapRAID will see the
`.snapshots` subvolume as a separate filesystem and warn you that it won't be
included in the parity. Excluding it explicitly will prevent you from receiving
this warning message from SnapRAID. Also, if you want to run `snapraid diff`
(as opposed to `snapraid-btrfs diff`), this will prevent SnapRAID from thinking
all the snapshots are new files.

When using `snapraid-btrfs` to sync, the `.snapshots` subvolume will appear as
an empty directory in the read-only snapshots, so excluding it in the SnapRAID
config file is unnecessary, but harmless. (The `.snapshots` directory is
excluded relative to the root of the data drives, so if your data drive is
mounted at `/foo/bar` then if using snapshot n it will exclude
`/foo/bar/.snapshots/n/snapshot/.snapshots`, and if using the live filesystem
it will exclude `/foo/bar/.snapshots`.)

Similarly, if you store any of your content files in subvolumes which have
mountpoints underneath the data subvolume, you should `exclude` those paths to
avoid receiving warnings from SnapRAID. For instance, if data is stored in
`/path/to/snapraid/1/data` and content in `/path/to/snapraid/1/content` then
no `exclude` would be required, but if the content subvolume is mounted
underneath the data subvolume, e.g. at `/path/to/snapraid/1/data/content`, then
an `exclude` statement would be needed to avoid a warning from SnapRAID. See
"What about the SnapRAID content files?" below.

### Q: Can I have multiple subvolumes on a single data drive?
A: `snapraid-btrfs` only uses one subvolume per data drive, which should
contain all the data which is to be protected by SnapRAID, and should have a
snapper config with the `SUBVOLUME` variable matching the path in the SnapRAID
config file. **Any files stored in other subvolumes on the data drives will NOT
be protected by the parity, even if those subvolumes are mounted below the path
specified in the SnapRAID config file.** This is because syncs will be done
using a read-only snapshot, where the subvolume mount point will appear to
SnapRAID as an empty directory. Also, SnapRAID currently sees separate btrfs
subvolumes as separate filesystems, so this wouldn't work even without
using snapshots.

In any case, it's desirable to have all the SnapRAID data files in a single
subvolume, since this makes snapshotting atomic, ensuring that after a
successful sync, the parity corresponds to a single snapshot of each data
drive.

### Q: What about the SnapRAID content files?
The SnapRAID "content" files should be stored in a separate subvolume to
prevent them from being snapshotted. `snapraid-btrfs` will display an error
message and refuse to run if this is not done.

### Q: Can I also manage snapshots manually with snapper?
A: Yes. `snapraid-btrfs` keeps track of its own snapshots using a snapper
userdata key, and will ignore any snapshots without that userdata key defined.
If you delete `snapraid-btrfs` snapshots using snapper, parity protection may
be lost, so it is recommended that you use the `snapraid-btrfs cleanup` command
instead, which will only delete snapshots when it is safe to do so (and will
ignore any snapshots without that userdata key specified). If you need to free
up space by deleting old snapshots, it is recommended that you complete a new
sync with a fresh set of snapshots (which will initially require no space since
they will be identical to the live filesystem), then run the
`snapraid-btrfs cleanup` command to delete the old ones.

### Q: Can I change the snapper userdata key that is used to track snapshots?
A: Yes. If the `SNAPRAID_USERDATA_KEY` environment variable is set,
`snapraid-btrfs` will use that as its userdata key. Otherwise, it will default
to `snapraid-btrfs`. Beware that if you change this, snapshots created before
the change will no longer be identified as having been created by
`snapraid-btrfs`.

### Q: Can I restore a previous snapshot?
A: Just like with "vanilla" SnapRAID, a fix can only restore the array to the
state that it was in at the time of the last sync. This is because the parity
files can only correspond to one snapshot at a time, and is a fundamental
limitation of SnapRAID due to its file-based nature.

The purpose of `snapraid-btrfs` is simply to ensure that modifying the array
after a sync doesn't delete any of the data that would be required for the
fix operation. If you want multiple snapshots protected by parity, you'll
need to use another solution such as mdadm or btrfs RAID that operates at
the filesystem or block device level.

The above only refers to what is possible with `snapraid fix` (whether or not
invoked via `snapraid-btrfs fix`). Of course, you can still revert individual
data disks, or the entire array, to a previous state, just as with any btrfs
filesystem. You just won't be able to make use of the parity to reconstruct
data in older snapshots if a disk fails.

### Q: What is the 'dsync' command and what is it for?
A: Short for `diff-sync`, this command creates a set of read-only snapshots,
runs a `snapraid diff`, and then asks for confirmation before running a
`snapraid sync` with the same snapshots. Since SnapRAID can only restore the
array to the state it was in at the time of the last sync, syncing is a
destructive action, and the `dsync` command allows the user to make sure the
new snapshots are okay before continuing with the sync. Since the sync will
only be run after the user has approved the diff, the `--force-empty` option is
passed through to `snapraid`. The behavior of this command is equivalent to
running `snapraid-btrfs diff` followed by
`snapraid-btrfs --interactive --use-snapshot-all=diff sync --force-empty`,
except that `snapraid-btrfs dsync` will only run the sync if `snapraid diff`
indicates that there have been changes since the last sync. Otherwise,
`snapraid-btrfs dsync` will simply exit after the diff.

### Q: What about pooling?
A: If you run `snapraid-btrfs pool` the symlinks created in your pool directory
(or in the directory specified with the `--pool-dir` option) will be to the
read-only snapshots instead of the live filesystem. This may or may not be what
you want; if you want the symlinks to point to the live filesystem, you can
still use the `snapraid pool` command as normal, or you can even have both in
different directories by making use of the `--pool-dir` option. If you do use
`snapraid-btrfs pool` you should re-run it after each sync. This will not only
keep the symlinks up to date with any changes, but also ensures that a
`snapraid-btrfs cleanup` operation doesn't result in broken symlinks that point
to deleted snapshots.

### Q: How do I stop using snapraid-btrfs?
A: Just complete a full sync, invoking SnapRAID directly and not via
`snapraid-btrfs`. Then your parity files will be up to date with the live
filesystem, and you can safely delete all snapshots using
`snapraid-btrfs cleanup-all` and have a regular SnapRAID configuration.

## Known issues
* SnapRAID won't be able to properly detect the UUID when using a snapshot, so
it won't be able to use inodes to detect move operations. As a workaround, you
can temporarily disable `snapraid-btrfs`, either globally by doing a regular
`snapraid sync`, or for specific drives by doing a `snapraid-btrfs sync` using
the `-U` option to select snapshot 0 (i.e., the live filesystem, in snapper
terminology) for the drives in question, moving the files, doing another sync
with `snapraid-btrfs` disabled, and then reenabling `snapraid-btrfs` by doing a
normal `snapraid-btrfs sync`.

## License
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
