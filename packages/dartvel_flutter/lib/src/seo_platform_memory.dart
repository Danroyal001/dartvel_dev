import '../dartvel_flutter.dart';

SeoProps _lastAppliedSeo = SeoProps.empty;

void applySeo(SeoProps props) {
  _lastAppliedSeo = props;
}

SeoProps get lastAppliedSeo => _lastAppliedSeo;
