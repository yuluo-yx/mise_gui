import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_cli_service.dart';

class ToolsRepository {
  ToolsRepository(this._miseCliService);

  final MiseCliService _miseCliService;

  Future<List<ToolRecord>> loadTools() async {
    return _miseCliService.fetchTools();
  }

  Future<ToolRecord> hydrateToolRemoteState(ToolRecord tool) async {
    return _miseCliService.hydrateToolRemoteState(tool);
  }
}
