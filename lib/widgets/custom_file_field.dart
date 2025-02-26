import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reactiveform/constants/colors.dart';
import 'package:reactiveform/string_constants.dart';
import 'package:reactiveform/widgets/form_field_wrapper.dart';

class CustomFileField extends StatelessWidget {
  final Map<String, dynamic> field;
  final String fieldName;
  final TextStyle fontFamily;
  final Color primaryColor;
  final Color buttonTextColor;
  final Function(List<Map<String, dynamic>>) onFilesUploaded;
  final List<Map<String, dynamic>> uploadedFiles;
  final Function(Map<String, dynamic>) onRemoveFile;
  static const double _iconSize = 24.0;
  static const int _maxFileSize = 3 * 1024 * 1024; // 3MB

  const CustomFileField({
    Key? key,
    required this.field,
    required this.fieldName,
    required this.fontFamily,
    required this.primaryColor,
    required this.buttonTextColor,
    required this.onFilesUploaded,
    required this.uploadedFiles,
    required this.onRemoveFile,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FormFieldWrapper(
      label: field['label'] ?? '',
      isRequired: field['required'] == true,
      labelStyle: fontFamily,
      description: field['description'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: buttonTextColor,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _showFilePickerOptions(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.upload_file, size: 28),
                const SizedBox(width: 12),
                Text(
                  StringConstants.uploadFiles,
                  style: fontFamily.copyWith(
                    fontSize: 16,
                    color: buttonTextColor,
                  ),
                ),
              ],
            ),
          ),
          if (uploadedFiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildFileList(),
          ],
        ],
      ),
    );
  }

  Widget _buildFileList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: uploadedFiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final file = uploadedFiles[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: _getFileTypeIcon(file['fileType']),
            title: Text(
              file['fileName'] ?? StringConstants.unnamedFile,
              style: fontFamily,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => onRemoveFile(file),
            ),
            onTap: () => _previewFile(context, file),
          ),
        );
      },
    );
  }

  void _showFilePickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.description_outlined, size: _iconSize),
                title: Text(StringConstants.chooseFile, style: fontFamily),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.collections_outlined, size: _iconSize),
                title: Text(StringConstants.chooseFromGallery, style: fontFamily),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(context, ImageSource.gallery);
                },
              ),
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined, size: _iconSize),
                  title: Text(StringConstants.takePhoto, style: fontFamily),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(context, ImageSource.camera);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        await _processFile(
          context,
          result.files.first.bytes!,
          result.files.first.name,
        );
      }
    } catch (e) {
      _showErrorSnackBar(context, StringConstants.errorSelectingFile);
    }
  }

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        await _processFile(context, bytes, image.name);
      }
    } catch (e) {
      _showErrorSnackBar(
        context,
        source == ImageSource.camera
            ? StringConstants.errorTakingPhoto
            : StringConstants.errorSelectingImage,
      );
    }
  }

  Future<void> _processFile(
    BuildContext context,
    Uint8List bytes,
    String fileName,
  ) async {
    if (bytes.length > _maxFileSize) {
      _showErrorSnackBar(context, StringConstants.fileSizeError);
      return;
    }

    final newFile = {
      'question_name': fieldName,
      'question_label': field['label'],
      'file': bytes,
      'fileName': fileName,
      'fileType': _getFileType(fileName),
      'mimeType': 'application/${fileName.split('.').last}',
    };

    onFilesUploaded([...uploadedFiles, newFile]);
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: fontFamily),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  String _getFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'pdf';
      case 'doc':
      case 'docx':
        return 'document';
      case 'xls':
      case 'xlsx':
        return 'spreadsheet';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return 'image';
      default:
        return 'other';
    }
  }

  Icon _getFileTypeIcon(String? fileType) {
    switch (fileType) {
      case 'pdf':
        return const Icon(Icons.picture_as_pdf);
      case 'document':
        return const Icon(Icons.description);
      case 'spreadsheet':
        return const Icon(Icons.table_chart);
      case 'image':
        return const Icon(Icons.image);
      default:
        return const Icon(Icons.insert_drive_file);
    }
  }

  Future<void> _previewFile(BuildContext context, Map<String, dynamic> file) async {
    if (file['fileType'] == 'image') {
      await showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: Text(
                  file['fileName'] ?? StringConstants.filePreview,
                  style: fontFamily,
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Image.memory(
                file['file'],
                errorBuilder: (_, __, ___) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    StringConstants.errorLoadingImage,
                    style: fontFamily,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            StringConstants.cannotPreviewFile,
            style: fontFamily,
          ),
        ),
      );
    }
  }
} 