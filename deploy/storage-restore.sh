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
exec 9>/run/edu-monitor-storage.lock
flock -n 9 || fail 'Another storage operation is running.'
[[ -f "$BASE/ready" ]] || fail 'Storage has not been initialized completely.'

read_id() {
    local value
    value=$(cat "$BASE/$1")
    [[ "$value" =~ ^[[:alnum:]:-]+$ ]] || fail "Invalid identifier: $1"
    printf '%s' "$value"
}
raid_uuid=$(read_id raid.uuid)
raid_fs_uuid=$(read_id raid-fs.uuid)
logs_fs_uuid=$(read_id logs-fs.uuid)
pv_uuid=$(read_id pv.uuid)
vg_uuid=$(read_id vg.uuid)

attach_loop() {
    local file=$1 device
    [[ -f "$file" && ! -L "$file" ]] || fail "Missing or invalid disk image: $file"
    device=$(losetup --noheadings --output NAME --associated "$file")
    [[ "$device" != *$'\n'* ]] || fail "Multiple loop devices for $file"
    if [[ -z "$device" ]]; then
        device=$(losetup -fP --show "$file")
    fi
    printf '%s' "$device"
}
loop1=$(attach_loop "$BASE/disk1.img")
loop2=$(attach_loop "$BASE/disk2.img")
loop3=$(attach_loop "$BASE/disk3.img")

for device in "$loop1" "$loop2"; do
    actual=$(mdadm --examine --export "$device" | sed -n 's/^MD_UUID=//p')
    [[ "$actual" == "$raid_uuid" ]] || fail "Unexpected RAID metadata on $device"
done

# An automatically assembled array can use a different /dev/md name.
raid_device=$(blkid -U "$raid_fs_uuid" || true)
if [[ -z "$raid_device" ]]; then
    [[ ! -e "$MD" ]] || fail "$MD is occupied; refusing to assemble over it."
    mdadm --assemble "$MD" --uuid="$raid_uuid" "$loop1" "$loop2"
    raid_device=$MD
fi
actual=$(mdadm --detail --export "$raid_device" | sed -n 's/^MD_UUID=//p')
[[ "$actual" == "$raid_uuid" ]] || fail 'Unexpected assembled RAID array.'

pvscan --cache "$loop3"
actual=$(pvs --noheadings -o pv_uuid "$loop3" | tr -d '[:space:]')
[[ "$actual" == "$pv_uuid" ]] || fail 'Unexpected LVM physical volume.'
actual=$(vgs --noheadings -o vg_uuid "$VG" | tr -d '[:space:]')
[[ "$actual" == "$vg_uuid" ]] || fail 'Unexpected LVM volume group.'
vgchange -ay "$VG"
[[ $(blkid -s UUID -o value "$LV") == "$logs_fs_uuid" ]] || fail 'Unexpected log filesystem.'

mount_checked() {
    local device=$1 target=$2 expected=$3 actual
    mkdir -p "$target"
    if mountpoint -q "$target"; then
        actual=$(findmnt -n -o UUID --mountpoint "$target")
        [[ "$actual" == "$expected" ]] || fail "A different filesystem is mounted at $target"
    else
        [[ -z $(find "$target" -mindepth 1 -maxdepth 1 -print -quit) ]] || fail "$target is not empty."
        mount "$device" "$target"
    fi
}
mount_checked "$raid_device" "$RAID_MOUNT" "$raid_fs_uuid"
mount_checked "$LV" "$LOG_MOUNT" "$logs_fs_uuid"
mkdir -p "$LOG_MOUNT/my-app"
