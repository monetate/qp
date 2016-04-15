# Don't try fancy stuff like debuginfo, which is useless on binary-only
# packages. Don't strip binary too
# Be sure buildpolicy set to do nothing
%define        __spec_install_post %{nil}
%define          debug_package %{nil}
%define        __os_install_post %{_dbpath}/brp-compress

%define name __NAME__

Summary: Query parallelizer
Name: %{name}
Version: __RPMVERSION__
Release: 1
License: Spec file is LGPL, binary rpm is gratis but non-distributable
Group: Applications/System
Source: %{name}-__RPMVERSION__.tar.gz

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root

%description
%{summary}

%prep
%setup -q

%build
# Empty

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}

# in builddir
cp -a * %{buildroot}

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root)
%doc
%{_bindir}/*

%changelog
