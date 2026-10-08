import '../../library/domain/models.dart';

/// Lets the sync controller hear about changes made through the repository
/// without the repository knowing about providers. Created in `main.dart` and
/// shared by the repository wrapper and the controller.
class LibraryChangeHook {
  void Function()? listener;
  void notify() => listener?.call();
}

/// Passes every call to [inner] and, after any write to the library, tells the
/// [hook] so the change is saved to the account. Reads and cover attachments
/// are not changes.
class SyncingRepository implements LibraryRepository {
  final LibraryRepository inner;
  final LibraryChangeHook hook;
  SyncingRepository(this.inner, this.hook);

  Future<T> _changed<T>(Future<T> write) async {
    final result = await write;
    hook.notify();
    return result;
  }

  @override
  Future<LibrarySnapshot> load() => inner.load();
  @override
  Future<Set<String>> coverPaths() => inner.coverPaths();
  @override
  Future<List<({String editionId, String source})>> coversToFetch() =>
      inner.coversToFetch();
  @override
  Future<void> attachCover(String editionId, String path) =>
      inner.attachCover(editionId, path);
  @override
  Future<Map<String, dynamic>> exportData() => inner.exportData();

  @override
  Future<String> saveBook({
    String? id,
    required String title,
    required String author,
    int? pageCount,
    String? language,
    String? coverPath,
    String? coverSource,
    required BookStatus status,
    PartialDate? finish,
    bool historical = false,
    String metadataSource = 'manual',
    String? seriesName,
    int? seriesNumber,
  }) => _changed(
    inner.saveBook(
      id: id,
      title: title,
      author: author,
      pageCount: pageCount,
      language: language,
      coverPath: coverPath,
      coverSource: coverSource,
      status: status,
      finish: finish,
      historical: historical,
      metadataSource: metadataSource,
      seriesName: seriesName,
      seriesNumber: seriesNumber,
    ),
  );

  @override
  Future<void> updatePage(String id, int page) =>
      _changed(inner.updatePage(id, page));
  @override
  Future<void> setStatus(String id, BookStatus status, {PartialDate? finish}) =>
      _changed(inner.setStatus(id, status, finish: finish));
  @override
  Future<void> setRating(String id, int? rating) =>
      _changed(inner.setRating(id, rating));
  @override
  Future<void> logSession(
    String id,
    DateTime date, {
    int? start,
    int? end,
    int? seconds,
  }) => _changed(
    inner.logSession(id, date, start: start, end: end, seconds: seconds),
  );
  @override
  Future<void> addPin(
    String id,
    String text,
    String type, {
    int? page,
    double? percent,
  }) => _changed(inner.addPin(id, text, type, page: page, percent: percent));
  @override
  Future<void> deletePin(String id) => _changed(inner.deletePin(id));
  @override
  Future<void> deleteBook(String id) => _changed(inner.deleteBook(id));
  @override
  Future<void> restoreData(Map<String, dynamic> data) =>
      _changed(inner.restoreData(data));
}
