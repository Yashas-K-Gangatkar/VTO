/**
 * Metro config — required for expo-three.
 *
 * `three/examples/jsm/*` imports reference bare specifiers like 'three'
 * that Metro can't resolve by default in a monorepo. The extraNodeModules
 * alias below makes those imports resolve to the actual `three` package
 * installed in apps/mobile/node_modules (or hoisted to the workspace root).
 *
 * Note on the WARN messages about three's package.json "exports" field:
 *   These are benign. three's package.json declares an "exports" map
 *   pointing to extensionless paths that don't exist on disk. Metro logs
 *   a warning, then falls back to file-based resolution which DOES find
 *   the actual .js files. You can ignore those warnings.
 */

const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const config = getDefaultConfig(__dirname);

// Merge our alias into the existing extraNodeModules (don't overwrite).
config.resolver.extraNodeModules = {
  ...(config.resolver.extraNodeModules || {}),
  three: path.resolve(__dirname, 'node_modules/three'),
};

module.exports = config;
