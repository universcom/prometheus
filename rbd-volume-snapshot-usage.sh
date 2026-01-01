#!/bin/bash
# short script to monitor rbd du output via the prometheus text_exporter
# mechanism
# data points exported for every image in all accessable clusters are
# ceph_rbd_image_bytes_provisioned
# ceph_rbd_image_bytes_used
me=`basename "$0"`

function clean_up {
    rm -rf /var/lock/$me.lock
}

if mkdir /var/lock/$me.lock; then
    (>&2 echo "$me lock succeeded")
    trap clean_up EXIT SIGINT SIGTERM
else
    (>&2 echo "$me couldn't take lock...giving up")
    exit 1
fi

awk_cmd='
{
print "ceph_rbd_image_bytes_used{image=\""$1"\",snapshot=\""$2"\",pool=\""pool"\"} " $4
print "ceph_rbd_image_bytes_provisioned{image=\""$1"\",snapshot=\""$2"\",pool=\""pool"\"} " $3
}'

echo '# HELP ceph_rbd_image_bytes_used Used space of an rbd image
# TYPE ceph_rbd_image_bytes_used gauge
# HELP ceph_rbd_image_bytes_provisioned Provisioned space of an rbd image
# TYPE ceph_rbd_image_bytes_provisioned gauge'


pool="$(ceph osd lspools 2>/dev/null | sed 's/[[:digit:]]\+ \([^,]*\),/\1 /g' | grep volumes | awk '{print $2}')"
for img in `rbd -p $pool ls`
do 
    if rbd -p "$pool" info "$img" >/dev/null 2>&1; then
        if rbd -p $pool info $img | grep -q "features:.*fast-diff.*"; then
            rbd -p $pool --format json du $img 2>/dev/null |
            jq ".images[] | [.name, .snapshot, .provisioned_size, .used_size] | @csv" |
            sed -e 's/^"//' -e 's/"$//' -e 's/\\"//g' | awk -F , -v pool=$pool "$awk_cmd"
        fi  
    fi
done
