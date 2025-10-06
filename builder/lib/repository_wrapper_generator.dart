import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'src/builder.dart';

Builder generateRepositoryWrapper(BuilderOptions options) {
  // Step 1
  return SharedPartBuilder(
    [RepositoryWrapperGenerator()], // Step 2
    'repository_wrapper_generator', // Step 3
  );
}
