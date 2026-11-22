exclude_files = ['meson.build']

if not meson.is_subproject()
	install_subdir('scenefx',
		install_dir: get_option('includedir') / versioned_name,
		exclude_files: exclude_files,
	)
endif
