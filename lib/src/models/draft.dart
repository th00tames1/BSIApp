import '../services/analysis_service.dart';
import '../theme.dart';
import 'survey.dart';

/// Mutable state carried through the survey flow (register → capture → analyse → result).
class SurveyDraft {
  String treeId = '';
  String site = '';
  String address = '';
  double? lat;
  double? lon;
  String species = '소나무';
  double dbhCm = 0;
  String memo = '';
  double poleLengthM = 3.0;
  String modelName = 'YOLO26s@640';
  String modelAsset = 'assets/models/bsi_seg_yolo26s_640.onnx';

  final Map<Azimuth, String> photos = {}; // captured photo path per azimuth
  final Map<Azimuth, AzimuthResult> results = {};
  BsiIntegration? integ;

  List<Azimuth> get capturedAzimuths =>
      Azimuth.values.where((a) => photos.containsKey(a)).toList();

  List<AzimuthResult> get faces =>
      Azimuth.values.where(results.containsKey).map((a) => results[a]!).toList();

  SurveyRecord toRecord() => SurveyRecord(
        treeId: treeId,
        site: site,
        address: address,
        lat: lat,
        lon: lon,
        species: species,
        dbhCm: dbhCm,
        memo: memo,
        modelName: modelName,
        poleLengthM: poleLengthM,
        faces: faces,
        bsi: integ?.bsi ?? double.nan,
        mortalityProb: integ?.mortality ?? double.nan,
        verdict: integ?.verdict ?? '',
        createdAt: DateTime.now(),
      );
}
