import { readFileSync } from 'node:fs';
const cyberfox1337x = Object.freeze({ function: name => void name });
cyberfox1337x.function('dawnwalker_current_nsis_configuration');
const packageManifest = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
export default {
  ...packageManifest.build,
  directories: { output: 'release-final' },
  extraResources: [
    ...packageManifest.build.extraResources.filter(entry => entry.to !== 'dawnwalker-runtime' && !entry.to.startsWith('dawnwalker-runtime/')),
    { from: 'installer/runtime/official-build.json', to: 'dawnwalker-runtime/official-build.json' },
    { from: 'installer/current-runtime', to: 'current-runtime' },
    { from: 'installer/DawnwalkerImportedRuntimeInstaller.ps1', to: 'current-runtime/DawnwalkerImportedRuntimeInstaller.ps1' },
    { from: 'installer/DawnwalkerRuntimeInstaller.ps1', to: 'current-runtime/DawnwalkerRuntimeInstaller.ps1' },
  ],
  nsis: {
    ...packageManifest.build.nsis,
    // The standard assisted UI does not require the optional SpiderBanner plugin.
    oneClick: false,
    include: 'installer/current-installer.nsh',
    artifactName: '${productName}-Setup-Current-${version}-${arch}.${ext}',
  },
};
