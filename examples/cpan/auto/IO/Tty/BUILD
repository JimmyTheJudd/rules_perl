# Copyright 2020 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package(default_visibility = ["//visibility:public"])

load("@io_bazel_rules_perl//perl:perl.bzl", "perl_xs")

perl_xs(
    name = "Tty",
    srcs = ["Tty.xs",],
    textual_hdrs = ["xssubs.c",],
    defines = [
        "HAVE_DEV_PTMX",
        "HAVE_GETPT",
        "HAVE_GRANTPT",
        "HAVE_POSIX_OPENPT",
        "HAVE_PTSNAME",
        "HAVE_PTSNAME_R",
        "HAVE_PTY_H",
        "HAVE_SIGACTION",
        "HAVE_SYS_STROPTS_H",
        "HAVE_TERMIOS_H",
        "HAVE_TERMIO_H",
        "HAVE_TTYNAME",
        "HAVE_UNLOCKP",
    ],
)

