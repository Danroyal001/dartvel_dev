// import 'dart:io' as io;
//
// import 'package:analyzer/dart/analysis/results.dart';
// import 'package:analyzer/error/error.dart';
// import 'package:analyzer/file_system/physical_file_system.dart';
// import 'package:analyzer/source/error_processor.dart';
// import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
// import 'package:analyzer/src/dart/analysis/byte_store.dart';
// import 'package:analyzer/src/dart/analysis/file_content_cache.dart';
// import 'package:collection/collection.dart';
//
// Future<void> main() async {
//   var workingDirectory = io.Directory(pkgAnalyzerPath);
//   if (!await workingDirectory.exists()) {
//     io.stderr.writeln(
//       'Error: Target path "$pkgAnalyzerPath" does not exist or is not a directory.',
//     );
//     io.exitCode = 1;
//     return;
//   }
//
//   // 2. Get the list of commits from after the specificSHA up to the masterBranchName.
//   // This phase was originally labeled "Phase 2" in your script.
//   print(
//     '\n--- Phase: Gathering Commits from after $specificSHA up to $masterBranchName ---',
//   );
//   List<String> commitsToProcess = [];
//   if (specificSHA.isNotEmpty) {
//     try {
//       // User wants to keep myPath as a direct argument to git log here.
//       var logResult = await _runCommand(
//         'git',
//         [
//           'log',
//           '$specificSHA..$masterBranchName',
//           '--format=%H',
//           '--reverse', // To get them in chronological order (oldest to newest in the range)
//           pkgAnalyzerPath, // Kept as per user's request for semantic consistency
//         ],
//         pkgAnalyzerPath, // Working directory for the command
//         printOutput: false,
//       );
//
//       if (logResult.exitCode == 0) {
//         commitsToProcess =
//             (logResult.stdout as String)
//                 .trim()
//                 .split('\n')
//                 .where(
//                   (s) => s.isNotEmpty && s.trim().length == 40,
//                 ) // Basic SHA validation
//                 .toList();
//         print(
//           'Found ${commitsToProcess.length} commits in the specified range.',
//         );
//       } else {
//         io.stderr.writeln(
//           'Error getting commit list from "$specificSHA" to "$masterBranchName":\n${logResult.stderr}',
//         );
//       }
//     } catch (e, s) {
//       io.stderr.writeln(
//         'Exception while getting commits from "$specificSHA" to "$masterBranchName": $e\n$s',
//       );
//     }
//   } else {
//     print('Skipping commit gathering because specificSHA is empty.');
//   }
//
//   // 3. Process each identified commit.
//   if (commitsToProcess.isNotEmpty) {
//     print('\n--- Processing ${commitsToProcess.length} Commits ---');
//     String? previousCommitSha;
//     var state = _StateBetweenCommits();
//     for (var currentCommitSha in commitsToProcess) {
//       String commitSummary = await _getCommitSummary(
//         currentCommitSha,
//         repoPath,
//       );
//       print('\n-----------------------------------------------------');
//       print('Processing Commit: $currentCommitSha');
//       print('Summary: $commitSummary'); // Print the summary
//       print('-----------------------------------------------------');
//
//       if (previousCommitSha != null) {
//         print('\nComparing $previousCommitSha with $currentCommitSha...');
//         try {
//           final diffResult = await _runCommand(
//             'git',
//             ['diff', '--name-only', previousCommitSha, currentCommitSha],
//             pkgAnalyzerPath,
//             printOutput: false, // We'll parse and print the stdout ourselves
//           );
//
//           if (diffResult.exitCode == 0) {
//             final changedFiles =
//                 (diffResult.stdout as String)
//                     .trim()
//                     .split('\n')
//                     .where((s) => s.isNotEmpty)
//                     .where((s) => s.endsWith('.dart'))
//                     .whereNot((s) => s.startsWith('runtime/'))
//                     .toList();
//
//             if (changedFiles.isNotEmpty) {
//               print(
//                 'Files changed since previous commit ($previousCommitSha):',
//               );
//               changedFiles.forEach((file) => print('  - $file'));
//             } else {
//               print(
//                 'No files changed between $previousCommitSha and $currentCommitSha.',
//               );
//             }
//           } else {
//             io.stderr.writeln(
//               'Error getting diff between $previousCommitSha and $currentCommitSha:\n${diffResult.stderr}',
//             );
//           }
//         } catch (e, s) {
//           io.stderr.writeln(
//             'Exception while getting diff between $previousCommitSha and $currentCommitSha: $e\n$s',
//           );
//         }
//       } else {
//         // This is the first commit being processed in this run.
//         print(
//           '\nProcessing the first commit in the list ($currentCommitSha). No previous commit in this sequence to compare against.',
//         );
//       }
//
//       await _processSingleCommit(state, currentCommitSha, pkgAnalyzerPath);
//       previousCommitSha = currentCommitSha;
//     }
//     print('\n--- Finished Processing All Commits ---');
//   } else {
//     print('No commits to process.');
//   }
//
//   // 4. Return to the initial Git state.
//   print('\n--- Restoring Initial Repository State ---');
//   await _runCommand(
//     'git',
//     ['checkout', 'master'],
//     pkgAnalyzerPath,
//     printOutput: false,
//   );
//   print('Successfully restored to: master.');
//   print('Script finished.');
// }
//
// const String masterBranchName = 'master';
// const String pkgAnalyzerPath = '$repoPath/pkg/analyzer';
// const repoPath = '/Users/scheglov/tmp/2025/2025-05-07/dart-sdk/sdk';
// const String specificSHA = 'c1366a48e9df1d7b9fdc5d197445e2f914fca4dc';
//
// /// Fetches the commit summary (first line of the commit message).
// Future<String> _getCommitSummary(String commitSha, String repoPath) async {
//   try {
//     final result = await _runCommand(
//       'git',
//       ['log', '-1', '--pretty=format:%s', commitSha], // %s gives the subject
//       repoPath,
//       printOutput: false, // We just need the stdout string
//     );
//     if (result.exitCode == 0) {
//       return (result.stdout as String).trim();
//     } else {
//       io.stderr.writeln(
//         'Warning: Could not get commit summary for $commitSha:\n${result.stderr}',
//       );
//       return '<Could not retrieve summary>';
//     }
//   } catch (e, s) {
//     io.stderr.writeln(
//       'Exception while getting commit summary for $commitSha: $e\n$s',
//     );
//     return '<Exception while retrieving summary>';
//   }
// }
//
// /// Processes a single commit: checks it out and runs dart analyze.
// Future<void> _processSingleCommit(
//   _StateBetweenCommits state,
//   String commitSha,
//   String repoPath,
// ) async {
//   // Step 1: Git checkout the commit
//   print('Step 1: Checking out $commitSha...');
//   io.ProcessResult checkoutResult;
//   try {
//     checkoutResult = await _runCommand(
//       'git',
//       ['checkout', commitSha],
//       repoPath,
//       printOutput: false, // Handling output below
//     );
//     if (checkoutResult.exitCode == 0) {
//       print('Successfully checked out $commitSha.');
//     } else {
//       io.stderr.writeln(
//         'Failed to checkout $commitSha. Stderr:\n${checkoutResult.stderr}',
//       );
//       print('Skipping further processing for this commit.');
//       return;
//     }
//   } catch (e, s) {
//     io.stderr.writeln('Exception during git checkout for $commitSha: $e\n$s');
//     print('Skipping further processing for this commit.');
//     return;
//   }
//
//   {
//     var timer = Stopwatch()..start();
//     var collection = AnalysisContextCollectionImpl(
//       resourceProvider: state.resourceProvider,
//       sdkPath: '/Users/scheglov/Applications/dart-sdk',
//       includedPaths: [pkgAnalyzerPath],
//       byteStore: state.byteStore,
//       fileContentCache: state.fileContentCache,
//       // performanceLog: PerformanceLog(io.stdout),
//       drainStreams: false,
//     );
//     print('[analysis][create: ${timer.elapsedMilliseconds} ms]');
//
//     for (var analysisContext in collection.contexts) {
//       for (var path in analysisContext.contextRoot.analyzedFiles()) {
//         if (path.endsWith('.dart')) {
//           analysisContext.driver.addFile(path);
//         }
//       }
//     }
//     print('[analysis][files: ${timer.elapsedMilliseconds} ms]');
//
//     collection.scheduler.events.listen((event) {
//       // print('[event: $event]');
//       if (event case AnalysisResultWithErrors result) {
//         var analysisOptions = result.session.analysisContext
//             .getAnalysisOptionsForFile(result.file);
//
//         var errors =
//             result.errors
//                 .where((diagnostic) {
//                   return diagnostic.errorCode.type != DiagnosticType.TODO;
//                 })
//                 .where((diagnostic) {
//                   var processor = ErrorProcessor.getProcessor(
//                     analysisOptions,
//                     diagnostic,
//                   );
//                   return processor == null || processor.severity != null;
//                 })
//                 .toList();
//         if (errors.isNotEmpty) {
//           print('[file: ${result.file}][errors: $errors]');
//         }
//       }
//     });
//     await collection.scheduler.waitForIdle();
//     {
//       print('\n' * 2);
//       var buffer = StringBuffer();
//       collection.scheduler.accumulatedPerformance.write(buffer: buffer);
//       print(buffer);
//     }
//     print('[analysis][total: ${timer.elapsedMilliseconds} ms]');
//   }
//
//   // Step 2: Run dart analyze (formerly Step 4)
//   if (0 == 1) {
//     print('\nStep 2: Running dart analyze on $repoPath...');
//     try {
//       var analyzeResult = await _runCommand(
//         'dart',
//         ['analyze', repoPath], // repoPath is the directory to analyze
//         repoPath, // workingDirectory for the dart command itself
//       ); // Full output is enabled by default in _runCommand
//
//       if (analyzeResult.exitCode == 0) {
//         print('Dart analyze completed successfully for $commitSha.');
//         if (analyzeResult.stdout.toString().trim().isEmpty &&
//             analyzeResult.stderr.toString().trim().isEmpty) {
//           print('No analysis issues found.');
//         }
//       } else {
//         // Stderr/Stdout for analyzeResult already printed by _runCommand if printOutput was true
//         print(
//           'Dart analyze reported issues or failed for $commitSha (exit code ${analyzeResult.exitCode}).',
//         );
//       }
//     } catch (e, s) {
//       io.stderr.writeln('Exception during dart analyze for $commitSha: $e\n$s');
//     }
//   }
//
//   print('Finished processing commit: $commitSha');
// }
//
// /// Helper function to run shell commands.
// Future<io.ProcessResult> _runCommand(
//   String executable,
//   List<String> arguments,
//   String workingDirectory, {
//   bool printOutput = true, // Made default true for general verbosity
//   bool throwOnError = false,
// }) async {
//   if (printOutput) {
//     print(
//       '  Running: $executable ${arguments.join(' ')} (in $workingDirectory)',
//     );
//   }
//   var result = await io.Process.run(
//     executable,
//     arguments,
//     workingDirectory: workingDirectory,
//     runInShell: true, // Kept as per previous version
//   );
//
//   if (printOutput) {
//     if (result.stdout.toString().isNotEmpty) {
//       print('  Stdout:\n${result.stdout}');
//     }
//     if (result.stderr.toString().isNotEmpty) {
//       // Using stderr.writeln for error messages to distinguish them
//       io.stderr.writeln('  Stderr:\n${result.stderr}');
//     }
//     if (result.exitCode != 0) {
//       io.stderr.writeln('  Command failed with exit code ${result.exitCode}');
//     }
//   }
//
//   if (throwOnError && result.exitCode != 0) {
//     throw Exception(
//       'Command "$executable ${arguments.join(' ')}" failed with exit code ${result.exitCode}.\nStderr: ${result.stderr}',
//     );
//   }
//   return result;
// }
//
// class _StateBetweenCommits {
//   final byteStore = MemoryByteStore();
//   final resourceProvider = PhysicalResourceProvider.INSTANCE;
//   late var fileContentCache = FileContentCache(resourceProvider);
// }
