#!/usr/bin/env bash

set -euxo pipefail

source "${RECIPE_DIR}/helpers/_build_install_qemu.sh"

# --- Main ---

# This script should install either in PREFIX, or for rattler-build in a subdirectory
# of PREFIX that the cache mechanism will be able to store and restore
install_dir="${CONDA_QEMU_INSTALL_DIR:-\"_conda_install\"}"
qemu_archs="${CONDA_QEMU_USER_ARCHS:-\"aarch64 ppc64le\"}"

local_install_dir="${PREFIX}"
if [[ "${install_dir}" != ${PREFIX} ]]; then
  local_install_dir="${SRC_DIR}/${install_dir}"
fi

# Compose the targets list
target_list="--target-list="
for qemu_arch in ${qemu_archs}
do
  if [ "${target_list}" != "--target-list=" ]; then
    target_list="${target_list},"
  fi
  target_list="${target_list}${qemu_arch}-linux-user"
done

# Build and install QEMU into the install directory
qemu_args=(${target_list})
_build_install_qemu "${SRC_DIR}/_conda-build" "${local_install_dir}" "${qemu_args[@]}"

# Copy the [de]activate scripts to $<install dir>/etc/conda/[de]activate.d.
for SCRIPT in "activate" "deactivate"
do
  mkdir -p "${local_install_dir}/etc/conda/${SCRIPT}.d"
  for qemu_arch in ${qemu_archs}
  do
    _qemu_arch="${qemu_arch}"
    if [[ "${qemu_arch}" == "ppc64le" ]]; then
      _qemu_arch="powerpc64le"
    fi
    sed -e "s|@QEMU_ARCH@|${_qemu_arch}|g" "${RECIPE_DIR}/scripts/${SCRIPT}.sh" > "${local_install_dir}/etc/conda/${SCRIPT}.d/qemu-execve-${qemu_arch}-${SCRIPT}.sh"
    chmod +x "${local_install_dir}/etc/conda/${SCRIPT}.d/qemu-execve-${qemu_arch}-${SCRIPT}.sh"
    done
done

# Rename execs
# for qemu_arch in ${qemu_archs}
# do
#   mv "${local_install_dir}"/bin/qemu-${qemu_arch} "${local_install_dir}"/bin/qemu-execve-${qemu_arch}
# done

# Only files installed in prefix will remain in the build cache
if [[ ${install_dir} != ${PREFIX} ]]; then
  tar -cf - -C "${SRC_DIR}" "${install_dir}" | tar -xf - -C "${PREFIX}"
fi