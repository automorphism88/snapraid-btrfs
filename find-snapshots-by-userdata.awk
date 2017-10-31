#!/usr/bin/awk -f

# This script searches the output of snapper ls either for snapshots which have
# a specified userdata key defined, or for snapshots where the specified
# userdata key is equal to a specified value. It was written for use by
# snapraid-btrfs, but also functions independently as a standalone program.

# The userdata key/value can be specified by passing the variables
# 'key' and 'value' using the -v option. The output is a list of snapshot
# numbers separated by newlines, with the snapshots matched as follows:
# - if key and value are both nonempty, match snapshots with userdata key=value
# - else if key is nonempty, match all snapshots with key defined
# - else match all snapshots

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

BEGIN { FS="|" } # snapper separates columns with '|' characters

NR<=2 { next } # first 2 lines are the header

{
    # remove spaces used to pad column width
    gsub(/[ ]+/,"",$2)
    if (key == "") {
        # match all snapshots
        print $2
    } else {
        # split userdata column into key=value pairs in case
        # multiple userdata keys are defined for a snapshot
        split($8,u,",")
        # construct a new array v where the keys are the values from u
        for (i in u) {
            gsub(/^[ ]+/,"",u[i])
            gsub(/[ ]+$/,"",u[i])
            if (value == "") {
                # We don't care about the value of the userdata key, so
                # split key=value pairs and store only the key as a key in v
                split(u[i],w,"=")
                v[w[1]]
            } else {
                # We care about both halves of the userdata key=value
                # pair, so store the whole key=value string as a key in v
                v[u[i]]
            }
        }
        # find and print our matches
        if (value == "") {
            if (key in v) {
                print $2
            }
        } else {
            if (key "=" value in v) {
                print $2
            }
        }
        # Wipe v so one match doesn't result in matching all subsequent lines
        split("",v," ") # delete v only works in gawk
    }
}
