# Copyright 2015 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Perl rules for Bazel"""

load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc:toolchain_utils.bzl", "find_cpp_toolchain")
load("@rules_cc//cc:action_names.bzl", "C_COMPILE_ACTION_NAME")

PERL_XS_COPTS = [
    "-fwrapv",
    "-fPIC",
    "-fno-strict-aliasing",
    "-D_LARGEFILE_SOURCE",
    "-D_FILE_OFFSET_BITS=64",
]

_perl_file_types = [".pl", ".pm", ".t"]
_perl_srcs_attr = attr.label_list(allow_files = _perl_file_types)

_perl_deps_attr = attr.label_list(
    allow_files = False,
    providers = ["transitive_perl_sources"],
)

_perl_data_attr = attr.label_list(
    allow_files = True,
)

_perl_main_attr = attr.label(
    allow_single_file = _perl_file_types,
)

_perl_env_attr = attr.string_dict()

def _collect_transitive_sources(ctx):
    return depset(
        ctx.files.srcs,
        transitive = [dep.transitive_perl_sources for dep in ctx.attr.deps],
        order = "postorder",
    )

def _get_main_from_sources(ctx):
    sources = ctx.files.srcs
    if len(sources) != 1:
        fail("Cannot infer main from multiple 'srcs'. Please specify 'main' attribute.", "main")
    return sources[0]

def _perl_library_implementation(ctx):
    transitive_sources = _collect_transitive_sources(ctx)
    return struct(
        runfiles = ctx.runfiles(collect_data = True),
        transitive_perl_sources = transitive_sources,
    )

def _perl_binary_implementation(ctx):
    toolchain = ctx.toolchains["@io_bazel_rules_perl//:toolchain_type"].perl_runtime
    interpreter = toolchain.interpreter

    toolchain_files = depset(toolchain.runtime)
    transitive_sources = _collect_transitive_sources(ctx)
    trans_runfiles = [toolchain_files, transitive_sources]

    main = ctx.file.main
    if main == None:
        main = _get_main_from_sources(ctx)

    ctx.actions.expand_template(
        template = ctx.file._wrapper_template,
        output = ctx.outputs.executable,
        substitutions = {
          "{interpreter}": interpreter.short_path,
          "{main}": main.short_path,
          "{workspace_name}": ctx.label.workspace_name or ctx.workspace_name,
        },
        is_executable = True,
    )

    return DefaultInfo(
        files = depset([ctx.outputs.executable]),
        runfiles = ctx.runfiles(
            transitive_files = depset([ctx.outputs.executable], transitive = trans_runfiles),
        ),
    )

def _perl_test_implementation(ctx):
    return _perl_binary_implementation(ctx)


def _perl_xs_cc_lib(ctx, toolchain, srcs):
    cc_toolchain = find_cpp_toolchain(ctx)
    xs_headers = toolchain.xs_headers

    includes = [f.dirname for f in xs_headers.to_list()]

    textual_hdrs = []
    for hdrs in ctx.attr.textual_hdrs:
        for hdr in hdrs.files.to_list():
            textual_hdrs.append(hdr)
            includes.append(hdr.dirname)

    includes = sets.make(includes)
    includes = sets.to_list(includes)

    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    (compilation_context, compilation_outputs) = cc_common.compile(
        actions = ctx.actions,
        name = ctx.label.name,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        srcs = srcs,
        defines = ctx.attr.defines,
        additional_inputs = textual_hdrs,
        private_hdrs = xs_headers.to_list(),
        includes = includes,
        user_compile_flags = ctx.attr.copts + PERL_XS_COPTS,
        compilation_contexts = []
    )

    (linking_context, linking_outputs) = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        name = ctx.label.name,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        linking_contexts = [],
    )

    return CcInfo(
        compilation_context = compilation_context,
        linking_context = linking_context,
    )

def _perl_xs_implementation(ctx):
    toolchain = ctx.toolchains["@io_bazel_rules_perl//:toolchain_type"].perl_runtime
    xsubpp = toolchain.xsubpp

    toolchain_files = depset(toolchain.runtime)
    trans_runfiles = [toolchain_files]

    gen = []
    cc_infos = []

    for src in ctx.files.srcs:
        out = ctx.actions.declare_file(paths.replace_extension(src.path, ".c"))
        name = "%s_c" % src.basename

        ctx.actions.run(
            outputs = [out],
            inputs = [src],
            arguments = ["-output", out.path, src.path],
            progress_message = "Translitterating %s to %s" % (src.short_path, out.short_path),
            executable = xsubpp,
            tools = toolchain_files
        )

        gen.append(out)

    cc_info = _perl_xs_cc_lib(ctx, toolchain, gen)
    cc_infos = [cc_info] + [dep[CcInfo] for dep in ctx.attr.deps]
    cc_info = cc_common.merge_cc_infos(cc_infos = cc_infos)
    lib = cc_info.linking_context.libraries_to_link.to_list()[0]
    dyn_lib = lib.dynamic_library

    # This is a hack to make the file name of the library sane for perl
    # TODO - Find a better way to do this _or_ canvas bazel for a
    # TODO - `ctx.actions.rename_file` to rename the file?
    # TODO - Also ... .so is linux / unix centric OSX is .dylib windows .dll
    output = ctx.actions.declare_file(ctx.label.name + ".so")
    ctx.actions.run_shell(
        outputs = [output],
        inputs = [dyn_lib],
        arguments = [dyn_lib.path, output.path],
        command = "cp $1 $2",
    )

    return [
        cc_info,
        DefaultInfo(files = depset([output])),
    ]


perl_library = rule(
    attrs = {
        "srcs": _perl_srcs_attr,
        "deps": _perl_deps_attr,
        "data": _perl_data_attr,
    },
    implementation = _perl_library_implementation,
    toolchains = ["@io_bazel_rules_perl//:toolchain_type"],
)

perl_binary = rule(
    attrs = {
        "srcs": _perl_srcs_attr,
        "deps": _perl_deps_attr,
        "data": _perl_data_attr,
        "main": _perl_main_attr,
        "_wrapper_template": attr.label(
            allow_single_file = True,
            default = "binary_wrapper.tpl",
        )
    },
    executable = True,
    implementation = _perl_binary_implementation,
    toolchains = ["@io_bazel_rules_perl//:toolchain_type"],
)

perl_test = rule(
    attrs = {
        "srcs": _perl_srcs_attr,
        "deps": _perl_deps_attr,
        "data": _perl_data_attr,
        "main": _perl_main_attr,
        "_wrapper_template": attr.label(
            allow_single_file = True,
            default = "binary_wrapper.tpl",
        )
    },
    executable = True,
    test = True,
    implementation = _perl_test_implementation,
    toolchains = ["@io_bazel_rules_perl//:toolchain_type"],
)

perl_xs = rule(
    attrs = {
        "srcs": attr.label_list(allow_files = [".xs"]),
        "textual_hdrs": attr.label_list(allow_files = True),
        "defines": attr.string_list(),
        "copts": attr.string_list(),
        "deps": attr.label_list(providers = [CcInfo]),
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    },
    implementation = _perl_xs_implementation,
    fragments = ["cpp"],
    toolchains = [
        "@io_bazel_rules_perl//:toolchain_type",
        "@bazel_tools//tools/cpp:toolchain_type"
    ],
)
