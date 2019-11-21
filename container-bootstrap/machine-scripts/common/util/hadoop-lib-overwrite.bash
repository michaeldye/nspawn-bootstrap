#!/bin/bash
# N.B. this could be (and should be) done much more surgically; there are lots of possible failures here

EXCL='(-tests|-sources)'

function fnames() {
  list=$1; shift

  cat $list | xargs -i -- basename {} | uniq | sed -r 's,[.0-9]+,XXX.,' | xargs
}

find $HBASE_HOME/ -maxdepth 2 -regex ".*hadoop.*.jar" | grep -vP '/hbase-' | grep -vP "$EXCL" > /tmp/hadoop-hbase-jars.list

cat /tmp/hadoop-hbase-jars.list | xargs -i -- basename {} | sed -r 's,([^-]*)-[.0-9]*(-tests)?.jar,\1,' | xargs -i -- find $HADOOP_HOME/share/hadoop -regex ".*{}.*.jar" | grep -vP "$EXCL" > /tmp/hadoop-share-jars.list

echo -e "Diff between HBase's bundled Hadoop jars (left) and Hadoop jars from our installation (right).\nThe version tag has been removed from files for a better diff.\n"
diff -y -w <(fnames /tmp/hadoop-hbase-jars.list | xargs -n1) <(fnames /tmp/hadoop-share-jars.list | xargs -n1)

# rem existing
xargs -i -a /tmp/hadoop-hbase-jars.list rm {}
cp /tmp/hadoop-hbase-jars.list $HBASE_HOME/deleted-hadoop-jars.list

# write from HADOOP_HOME
xargs -a /tmp/hadoop-share-jars.list cp --target-directory=$HBASE_HOME/lib/ |& tee $HADOOP_HOME/copied-hadoop-jars.out
cp /tmp/hadoop-share-jars.list $HBASE_HOME/copied-hadoop-jars.list
