#!/usr/bin/env bash
set -euo pipefail

BASE=/var/lib/edu-resource-monitor
MD=/dev/md/edu-monitor
VG=edu_monitor_data
LV=/dev/edu_monitor_data/logs
RAID_MOUNT=/mnt/edu-monitor-raid
LOG_MOUNT=/mnt/edu-monitor-logs

fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail 'Run as root.'
for command in dd losetup mdadm pvcreate vgcreate lvcreate mkfs.ext4 blkid vgs mountpoint flock; do
    command -v "$command" >/dev/null || fail "Missing command: $command"
done
exec 9>/run/edu-monitor-storage.lock
flock -n 9 || fail 'Another storage operation is running.'

[[ ! -e "$BASE" ]] || fail "$BASE already exists; refusing to overwrite storage."
[[ ! -e "$MD" ]] || fail "$MD already exists."
[[ ! -e "$LV" ]] || fail "$LV already exists."
existing_vgs=$(vgs --noheadings -o vg_name)
if printf '%s\n' "$existing_vgs" | awk '{$1=$1; print}' | grep -Fxq "$VG"; then
    fail "$VG already exists."
fi
for path in "$RAID_MOUNT" "$LOG_MOUNT"; do
    [[ ! -e "$path" ]] || fail "$path already exists; inspect it before proceeding."
done

# mkdir without -p reserves a new directory; an interrupted run is not overwritten.
mkdir -m 700 "$BASE"
for number in 1 2 3; do
    dd if=/dev/zero of="$BASE/disk$number.img" bs=1M count=512 status=progress
done
loop1=$(losetup -fP --show "$BASE/disk1.img")
loop2=$(losetup -fP --show "$BASE/disk2.img")
loop3=$(losetup -fP --show "$BASE/disk3.img")

mdadm --create "$MD" --metadata=1.2 --level=1 --raid-devices=2 --run "$loop1" "$loop2"
mkfs.ext4 "$MD"
pvcreate "$loop3"
vgcreate "$VG" "$loop3"
lvcreate -L 200M -n logs "$VG"
mkfs.ext4 "$LV"

mdadm --detail --export "$MD" | sed -n 's/^MD_UUID=//p' > "$BASE/raid.uuid"
blkid -s UUID -o value "$MD" > "$BASE/raid-fs.uuid"
blkid -s UUID -o value "$LV" > "$BASE/logs-fs.uuid"
pvs --noheadings -o pv_uuid "$loop3" | tr -d '[:space:]' > "$BASE/pv.uuid"
vgs --noheadings -o vg_uuid "$VG" | tr -d '[:space:]' > "$BASE/vg.uuid"
for file in raid.uuid raid-fs.uuid logs-fs.uuid pv.uuid vg.uuid; do
    [[ -s "$BASE/$file" ]] || fail "Missing storage identifier: $file"
done

mkdir "$RAID_MOUNT" "$LOG_MOUNT"
touch "$BASE/ready"
flock -u 9
"$(dirname -- "$0")/storage-restore.sh"
printf 'Created RAID at %s and LVM at %s.\n' "$RAID_MOUNT" "$LOG_MOUNT"
