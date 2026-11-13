#!/usr/bin/env node
import { runCLI } from '../scripts/npm-cli.mjs';
process.exitCode = runCLI(process.argv.slice(2));
