
!--------------------------------------------------------------------------
!
!    Copyright (C) 2017-2019  Georg Umgiesser
!
!    This file is part of SHYFEM.
!
!    SHYFEM is free software: you can redistribute it and/or modify
!    it under the terms of the GNU General Public License as published by
!    the Free Software Foundation, either version 3 of the License, or
!    (at your option) any later version.
!
!    SHYFEM is distributed in the hope that it will be useful,
!    but WITHOUT ANY WARRANTY; without even the implied warranty of
!    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
!    GNU General Public License for more details.
!
!    You should have received a copy of the GNU General Public License
!    along with SHYFEM. Please see the file COPYING in the main directory.
!    If not, see <http://www.gnu.org/licenses/>.
!
!    Contributions to this file can be found below in the revision log.
!
!--------------------------------------------------------------------------

c revision log :
c
c 19.05.2020	ccf	started from scratch
c
c****************************************************************

        program shyparts

c partitions grd file using the METIS library
c requires metis-5.1.0.tar.gz

	use mod_geom
	use evgeom
	use basin
	use clo
	use basutil
	use shympi
        use grd

	implicit none

	integer		      :: k,ie,ii,l,ic
        integer               :: nparts			!number of parts to partition the mesh
	integer, allocatable  :: eptr(:) 		!index for eind
	integer, allocatable  :: eind(:) 		!list of nodes in elements
	integer, pointer      :: vwgt(: )=>null() 	!weights of the vertices
        integer, pointer      :: vsize=>null()		!size of the nodes
        real(kind=8), pointer :: tpwgts(: )=>null()	!desired weight for each partition

        integer               :: objval			!edge-cut or the total comm vol
	integer, allocatable  :: epart(:)		!partition vector for the elements
	integer, allocatable  :: npart(:)		!partition vector for the nodes
	integer               :: options(40)		!metis options
        integer, allocatable  :: nc(:)			!array for check

        character*3 numb
	character*80 grdfile,basnam,name

c-----------------------------------------------------------------
c read in basin
c-----------------------------------------------------------------

        call shyfem_copyright('shyparts - partitioning a SHYFEM grid')
	write(6,*) 'Partition with METIS'
	write(6,*) ''

        call shyparts_init(grdfile,nparts)
        call shympi_init(.false.)

        if( grdfile == ' ' ) call clo_usage
        call read_command_line_file(grdfile)

c-----------------------------------------------------------------
c initialize modules
c-----------------------------------------------------------------

        call ev_init(nel)
        call set_ev

        call mod_geom_init(nkn,nel,ngr)
        call set_geom

c-----------------------------------------------------------------
c initialiaze arrays
c-----------------------------------------------------------------

        allocate(eptr(nel+1))
        allocate(eind(nel*3))
        allocate(epart(nel))
        allocate(npart(nkn))
        epart = 0
        npart = 0

c-----------------------------------------------------------------
c set up METIS eptr and eind arrays structures
c-----------------------------------------------------------------

        eptr(1)=1
        do ie = 1,nel
          do ii = 1,3
            l = eptr(ie) + ii -1
            eind(l) = nen3v(ii,ie)
          end do
          eptr(ie+1) = eptr(ie) + 3
        enddo 

c-----------------------------------------------------------------
c Set METIS options
c For the full list and order of options see metis-5.1.0/include/metis.h
c and the documentation in manual/manual.pdf
c-----------------------------------------------------------------

        call METIS_SetDefaultOptions(options)
        options(1) = 1		!PTYPE (0=rb,1=kway)
        options(2) = 1		!OBJTYPE (0=cut,1=vol)
        options(12) = 1		!CONTIG (0=defoult,1=force contiguous)
        options(18) = 1		!NUMBERING (0 C-style, 1 Fortran-style)

c-----------------------------------------------------------------
c Call METIS for patitioning on nodes
c-----------------------------------------------------------------

        call METIS_PartMeshNodal(nel, nkn, eptr, eind, vwgt, vsize, 
     +       nparts, tpwgts, options, objval, epart, npart)

c-----------------------------------------------------------------
c check partition
c-----------------------------------------------------------------

	call link_set_stop(.false.)	!do not stop after error

        iarnv = npart
        iarv = epart
        call check_connectivity
        call check_connections

	call link_set_stop(.true.)

!-----------------------------------------------------------------
! write partition information to terminal
!-----------------------------------------------------------------

	write(6,*) ''
        allocate(nc(0:nparts))
        nc = 0
        do k=1,nkn
          ic = iarnv(k)
          if( ic < 1 .or. ic > nparts ) then
            write(6,*) 'ic,nparts: ',ic,nparts
            stop 'error stop bas_partition: internal error (1)'
          end if
          nc(ic) = nc(ic) + 1
        end do
        write(6,*) 'Information on domains: '
        write(6,*) '   domain     nodes   percent'
        do ic=1,nparts
          write(6,'(2i10,f10.2)') ic,nc(ic),(100.*nc(ic))/nkn
        end do

c-----------------------------------------------------------------
c write grd files
c-----------------------------------------------------------------

	write(numb,'(i3)') nparts
        numb = adjustl(numb)
        basnam = grdfile
        call delete_extension(basnam,'.grd')

        ianv = npart
        name = trim(basnam)//'.'//trim(numb)//'.'//'node.grd'
        call grd_write(name)
	write(6,*) ''
        write(6,*) 'Grid with partition on nodes in file: ',name

        iaev = epart
        name = trim(basnam)//'.'//trim(numb)//'.'//'elem.grd'
        call grd_write(name)
        write(6,*) 'Grid with partition on elements in file: ',name 

c-----------------------------------------------------------------
c end of routine
c-----------------------------------------------------------------

        end

c*******************************************************************
c*******************************************************************
c*******************************************************************

	subroutine read_command_line_file(file)

	use basin
	use basutil

	implicit none

	character*(*) file
	logical is_grd_file

	if( basin_is_basin(file) ) then
	  write(6,*) 'reading BAS file ',trim(file)
	  call basin_read(file)
	  breadbas = .true.
	else if( is_grd_file(file) ) then
	  write(6,*) 'reading GRD file ',trim(file)
	  call grd_read(file)
	  call grd_to_basin
	  call estimate_ngr(ngr)
	  breadbas = .false.
	else
	  write(6,*) 'Cannot read this file: ',trim(file)
	  stop 'error stop read_given_file: format not recognized'
	end if

	end

c*******************************************************************

	subroutine shyparts_init(grdfile,nparts)

	use clo

	implicit none

	character*(*) grdfile
        integer nparts

	call clo_init('shyparts','grd-file','3.0')

        call clo_add_info('partitioning of grd file with METIS')

	call clo_add_sep('options for partitioning')
        call clo_add_option('nparts',-1,'number of partitions')

	call clo_parse_options

	call clo_check_files(1)
	call clo_get_file(1,grdfile)

        call clo_get_option('nparts',nparts)
        if (nparts < 2 ) then
          write(6,*) 'nparts: ',nparts
	  stop 'error stop shyparts_init: nparts < 2'
        end if

	end

c*******************************************************************

	subroutine node_test
	end

c*******************************************************************

