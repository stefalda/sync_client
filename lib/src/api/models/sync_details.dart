import 'dart:convert';

import './sync_data.dart';

/// Classe contenente le informazioni di sincronizzazione
class SyncDetails {
  ///Elenco degli ID rifiutati dal server e quindi da rimuovere anche su client,
  /// questo elenco può essere utilizzato per visualizzare interfaccia i
  /// conflitti emersi e i dati persi
  List<String>? outdatedRowsGuid = List.empty(growable: true);

  /// Elenco delle modifiche da apportare al DB locale sulla base di quanto
  /// presente sul server
  List<SyncData> data = List.empty(growable: true);

  /// Paginazione: true se il server ha altre modifiche oltre a questa pagina.
  bool hasMore = false;

  /// Cursore da rimandare per ottenere la pagina successiva.
  int nextCursor = 0;

  /// Versione di schema più alta tra i device dell'utente (0 = server vecchio).
  int maxSchemaVersion = 0;

  SyncDetails.fromJson(Map<String, dynamic> json) {
    hasMore = json['hasMore'] == true;
    nextCursor = (json['nextCursor'] as num?)?.toInt() ?? 0;
    maxSchemaVersion = (json['maxSchemaVersion'] as num?)?.toInt() ?? 0;
    outdatedRowsGuid = json['outdatedRowsGuid'].cast<String>();
    if (json['data'] != null) {
      json['data'].forEach((v) {
        if (v is! Map) {
          v = jsonDecode(v);
        }
        data.add(SyncData.fromMap(v));
      });
    }
  }
}
