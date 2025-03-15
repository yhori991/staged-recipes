#!/usr/bin/env bash

set -o xtrace -o nounset -o pipefail -o errexit

mkdir -p ${PREFIX}/bin
mkdir -p ${PREFIX}/libexec/${PKG_NAME}
export PATH="${DOTNET_ROOT}/dotnet:${PATH}"

dotnet_version=$(dotnet --version)
framework_version=${dotnet_version%.*}

# Patch the project files to use the correct .NET version
find lib src tests -name "*.csproj" -exec sed -i -E \
  -e "s/([>;])net6.0([<;])/\1net${framework_version}\2/" \
  {} \;
#DEBUG:  -e "s|^((\s+)<PropertyGroup>)|\1\n\2\2<NoWarn>CS0168;CS0219;CS8981;SYSLIB0050;SYSLIB0051</NoWarn>|" \
#Needed?  -e 's|^(\s+)<(Package)?Reference\s+Include="Mono.Posix".*\n||g' \
find . -type d -name "obj" -exec rm -rf {} +
find . -type d -name "bin" -exec rm -rf {} +

# Typo in release, already fixed in master
# This is solved in upstream master - Also, patching with leading tabs seems to fail with rattler
sed -i -E 's/(ReleaseHeadless\|Any .+ = )Debug/\1Release/' Renode_NET.sln

# Prevent CMake build since we provide the binaries
mkdir -p ${SRC_DIR}/src/Infrastructure/src/Emulator/Cores/bin/Release/lib
ln -s ${PREFIX}/lib/renode-cores/* ${SRC_DIR}/src/Infrastructure/src/Emulator/Cores/bin/Release/lib

# Remove the C cores that are not built in this recipe
rm -f ${SRC_DIR}/src/Infrastructure/src/Emulator/Cores/translate*.cproj

chmod +x tools/{building,packaging}/*.sh
${RECIPE_DIR}/helpers/renode_build_with_dotnet.sh ${framework_version}

# Install procedure
mkdir -p $PREFIX/libexec/${PKG_NAME}
cp -r output/bin/Release/net${framework_version}/* $PREFIX/libexec/${PKG_NAME}/

mkdir -p $PREFIX/share/${PKG_NAME}/scripts
mkdir -p $PREFIX/share/${PKG_NAME}/platforms
mkdir -p $PREFIX/share/${PKG_NAME}/tests
mkdir -p $PREFIX/opt/${PKG_NAME}/tools

cp -r scripts/* $PREFIX/share/${PKG_NAME}/scripts/
cp -r platforms/* $PREFIX/share/${PKG_NAME}/platforms/
cp -r tests/* $PREFIX/share/${PKG_NAME}/tests/
cp lib/resources/styles/robot.css $PREFIX/share/${PKG_NAME}/tests

# Refactoring into separate companion packages
# cp -r tools/metrics_analyzer $PREFIX/opt/${PKG_NAME}/tools
# cp -r tools/execution_tracer $PREFIX/opt/${PKG_NAME}/tools
# cp -r tools/gdb_compare $PREFIX/opt/${PKG_NAME}/tools
# cp -r tools/sel4_extensions $PREFIX/opt/${PKG_NAME}/tools

mkdir -p license-files
if [[ "${target_platform}" == "osx-*" ]]; then
  tools/packaging/common_copy_licenses.sh license-files macos
else
  tools/packaging/common_copy_licenses.sh license-files linux
fi

sed -i.bak "s#os\.path\.join(this_path, '\.\./lib/resources/styles/robot\.css')#os.path.join(this_path,'robot.css')#g" $PREFIX/share/${PKG_NAME}/tests/robot_tests_provider.py
rm $PREFIX/share/${PKG_NAME}/tests/robot_tests_provider.py.bak

mkdir -p $PREFIX/bin/
cat > $PREFIX/bin/renode <<"EOF"
#!/bin/sh
exec "${DOTNET_ROOT}"/dotnet exec "${CONDA_PREFIX}"/libexec/renode-cli/Renode.dll "$@"
EOF
chmod +x ${PREFIX}/bin/renode


cat > $PREFIX/bin/renode-test <<"EOF"
#!/usr/bin/env bash

STTY_CONFIG=`stty -g 2>/dev/null`
python3 "${CONDA_PREFIX}"/opt/renode-cli/tests/run_tests.py --robot-framework-remote-server-full-directory "${CONDA_PREFIX}"/libexec/renode-cli "$@"
RESULT_CODE=$?
if [ -n "${STTY_CONFIG:-}" ]
then
    stty "$STTY_CONFIG"
fi
exit $RESULT_CODE
EOF
chmod +x ${PREFIX}/bin/renode-test
