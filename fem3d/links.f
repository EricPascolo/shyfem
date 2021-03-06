
!--------------------------------------------------------------------------
!
!    Copyright (C) 2003,2005,2009-2013,2015,2017-2019  Georg Umgiesser
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

c geometric routines (static)
c
c contents :
c
c revision log :
c
c 10.08.2003	ggu	new routines for ieltv, kantv
c 18.10.2005	ggu	more debug output, new routines get_link, get_lenk
c 06.04.2009	ggu	changed nlidim to nlkddi
c 23.03.2010	ggu	changed v6.1.1
c 30.03.2011	ggu	bverbose introduced
c 14.04.2011	ggu	changed VERS_6_1_22
c 30.03.2012	ggu	changed VERS_6_1_51
c 25.10.2013	ggu	changed VERS_6_1_68
c 21.05.2015	ggu	changed VERS_7_1_11
c 30.05.2015	ggu	new subroutine mklenkii to compute lenkiiv
c 10.07.2015	ggu	changed VERS_7_1_50
c 24.07.2015	ggu	changed VERS_7_1_82
c 02.12.2015	ggu	routines get_link() and get_lenk() deleted
c 16.12.2015	ggu	changed VERS_7_3_16
c 18.12.2015	ggu	changed VERS_7_3_17
c 05.12.2017	ggu	changed VERS_7_5_39
c 19.04.2018	ggu	changed VERS_7_5_45
c 26.04.2018	ggu	changed VERS_7_5_46
c 16.02.2019	ggu	changed VERS_7_5_60
c 20.05.2020	ggu	bstop implemented
c 21.05.2020	ggu	module implemented
c
c****************************************************************
c****************************************************************
c****************************************************************

!===========================================================
	module link_structure
!===========================================================

	implicit none

	logical, save :: bverbose = .false.	!write more information
	logical, save :: bstop    = .true.	!stop after error

!===========================================================
	end module link_structure
!===========================================================

c****************************************************************
c****************************************************************
c****************************************************************

	subroutine link_set_verbose(bset)
	use link_structure
	implicit none
	logical bset
	bverbose = bset
	end

	subroutine link_set_stop(bset)
	use link_structure
	implicit none
	logical bset
	bstop = bset
	end

c****************************************************************
c****************************************************************
c****************************************************************

	subroutine estimate_max_grade(nkn,nel,nen3v,ngrm)

	implicit none

	integer nkn,nel
	integer nen3v(3,nel)
	integer ngrm

	integer ie,ii,k
	integer ic(nkn)

	ic = 0

	do ie=1,nel
	  do ii=1,3
	    k = nen3v(ii,ie)
	    ic(k) = ic(k) + 1
	  end do
	end do

	ngrm = maxval(ic)	!too small for boundary nodes

	end
	
c****************************************************************

	subroutine nn_insert(ngrm,k,nnode,node_list)

	implicit none

	integer ngrm,k
	integer nnode
	integer node_list(2*ngrm)

	integer i

	do i=1,nnode
	  if( node_list(i) == k ) exit
	end do

	if( i > nnode ) then
	  nnode = nnode + 1
	  if( nnode > 2*ngrm ) goto 99
	  node_list(nnode) = k
	else
	  node_list(i) = node_list(nnode)
	  nnode = nnode - 1
	end if

	return
   99	continue
	write(6,*) nnode,2*ngrm
	stop 'error stop nn_insert: nnode > 2*ngrm'
	end

c****************************************************************

	subroutine nn_clean(nnode,node_list)

	implicit none

	integer nnode
	integer node_list(nnode)

	integer i,k,j

	do i=1,nnode
	  if( i > nnode ) exit
	  k = node_list(i)
	  do j=i+1,nnode
	    if( node_list(j) == k ) exit
	  end do
	  if( j <= nnode ) then
	    node_list(j) = node_list(nnode)
	    nnode = nnode - 1
	  end if
	end do
	    
	end

c****************************************************************

        subroutine make_links(nkn,nel,nen3v,ilinkv,lenkv)

c sets up vector with element links and a pointer to it
c
c only array nen3v is needed, no aux array is needed
c
c ilinkv    pointer to links
c lenkv     link to element numbers
c
c number of links of node n : nl = ilinkv(n+1)-ilinkv(n)
c links of node n           : ( lenkv ( ilinkv(n)+i ), i=1,nl )

        implicit none

c arguments
        integer nlkddi
        integer nkn
        integer nel
        integer nen3v(3,nel)
        integer ilinkv(nkn+1)
        integer lenkv(*)
c local
        logical binside
        integer nloop
        integer ie,i,n,k,ii,iii,kk
        integer ip,ip0,ip1,ipe
        integer ie0,ie1,k0,k1
        integer nfill
	integer ne,nn,ngrm
	integer nin,nbn,ner
	logical bwrite

	integer, allocatable :: elem_list(:,:)
	integer, allocatable :: node_list(:,:)
	integer, allocatable :: nelem(:)
	integer, allocatable :: nnode(:)
c functions
        integer knext,kbhnd
	integer ipext,ieext

	ip = 0
	ip1 = 0

c-------------------------------------------------------------------
c first the total number of elements (links) for each node is established
c-------------------------------------------------------------------

	call estimate_max_grade(nkn,nel,nen3v,ngrm)

	allocate(elem_list(ngrm,nkn))
	allocate(node_list(2*ngrm,nkn))
	allocate(nelem(nkn))
	allocate(nnode(nkn))
	
	nelem = 0
	nnode = 0

        do ie=1,nel
          do ii=1,3
            k=nen3v(ii,ie)

	    ne = nelem(k) + 1
	    if( ne > ngrm ) goto 99
	    elem_list(ne,k) = ie
	    nelem(k) = ne

	    iii = ii

	    iii = mod(iii,3) + 1
            kk=nen3v(iii,ie)
	    nn = nnode(k) + 1
	    if( nn > 2*ngrm ) goto 99
	    node_list(nn,k) = kk
	    nnode(k) = nn

	    iii = mod(iii,3) + 1
            kk=nen3v(iii,ie)
	    nn = nnode(k) + 1
	    if( nn > 2*ngrm ) goto 99
	    node_list(nn,k) = kk
	    nnode(k) = nn
	  end do
	end do
	
	do k=1,nkn
	  call nn_clean(nnode(k),node_list(:,k))
	end do

	nin = 0
	nbn = 0
	ner = 0
	do k=1,nkn
	  nn = nnode(k)
	  ne = nelem(k)
	  if( nn == ne ) then
	    nin = nin + 1
	  else if( nn == ne+1 ) then
	    nbn = nbn + 1
	  else
	    write(6,*) 'error in structure: ',nn,ne,k
	    ner = ner + 1
	  end if
	end do

	write(6,*) 'make_links: ',nin,nbn,ner,nkn
	if( nin+nbn+ner /= nkn ) then
	  stop 'error stop make_links: internal error (2)'
	end if

c-------------------------------------------------------------------
c now create pointer into array
c-------------------------------------------------------------------


c-------------------------------------------------------------------
c now enter the element numbers of the links
c-------------------------------------------------------------------


c-------------------------------------------------------------------
c sort element entries
c-------------------------------------------------------------------

	return
   99	continue
	write(6,*) ne,nn,ngrm
	stop 'error stop make_links: internal error (1)'
	end

c****************************************************************

        subroutine mklenk(nlkddi,nkn,nel,nen3v,ilinkv,lenkv)

c sets up vector with element links and a pointer to it
c
c only array nen3v is needed, no aux array is needed
c
c ilinkv    pointer to links
c lenkv     link to element numbers
c
c number of links of node n : nl = ilinkv(n+1)-ilinkv(n)
c links of node n           : ( lenkv ( ilinkv(n)+i ), i=1,nl )

        implicit none

c arguments
        integer nlkddi
        integer nkn
        integer nel
        integer nen3v(3,nel)
        integer ilinkv(nkn+1)
        integer lenkv(*)
c local
        logical binside
        integer nloop
        integer ie,i,n,k
        integer ip,ip0,ip1,ipe
        integer ie0,ie1,k0,k1
        integer nfill
c functions
        integer knext,kbhnd
	integer ipext,ieext

	ip = 0
	ip1 = 0

c-------------------------------------------------------------------
c first the total number of elements (links) for each node is established
c-------------------------------------------------------------------

        do k=1,nkn
          ilinkv(k)=1           !one more link -> will be corrected later
        end do

        do ie=1,nel
          do i=1,3
            k=nen3v(i,ie)
            ilinkv(k)=ilinkv(k)+1
          end do
        end do

c-------------------------------------------------------------------
c now create pointer into array
c-------------------------------------------------------------------

        n=0
        do k=1,nkn
          i=ilinkv(k)
          ilinkv(k)=n
          n=n+i
        end do
        ilinkv(nkn+1)=n

        if( n .gt. nlkddi ) goto 98

c-------------------------------------------------------------------
c now enter the element numbers of the links
c-------------------------------------------------------------------

        do i=1,ilinkv(nkn+1)
          lenkv(i)=0
        end do

        do ie=1,nel
          do i=1,3
            k=nen3v(i,ie)
	    if( k .gt. nkn ) goto 97
            ip=ilinkv(k)+1      !first entry
            ip1=ilinkv(k+1)     !last possible entry
            do while(ip.le.ip1.and.lenkv(ip).ne.0)
              ip=ip+1
            end do
            if(ip.gt.ip1) goto 99       !error 1
            lenkv(ip)=ie
          end do
        end do

c-------------------------------------------------------------------
c sort element entries
c-------------------------------------------------------------------

        do k=1,nkn

          ip0=ilinkv(k)+1
          ip1=ilinkv(k+1)

c         ----------------------------------------------------------
c         if k is boundary node, find first element (in anti-clockwise sense)
c         ----------------------------------------------------------

          binside = .true.
          nloop = 0
          ip=ip0

          do while( binside .and. nloop .le. ip1-ip0 )
            ipe=ip
            k1=knext(k,lenkv(ipe))
            ip=ip0
            do while(ip.le.ip1.and.lenkv(ip).ne.0)
              if(knext(k1,lenkv(ip)).eq.k) goto 1
              ip=ip+1
            end do
            binside = .false.
    1       continue
            nloop = nloop + 1
          end do

c         --------------------------------------------------------
c         at ipe is first element --> now swap
c         --------------------------------------------------------

          if( .not. binside ) then      !boundary element
            ie=lenkv(ip0)
            lenkv(ip0)=lenkv(ipe)
            lenkv(ipe)=ie
          end if

c         ----------------------------------------------------------
c         sort next elements
c         ----------------------------------------------------------

          do while(ip0.le.ip1-1.and.lenkv(ip0).ne.0)
            k1=kbhnd(k,lenkv(ip0))
            ip=ip0+1
            do while(ip.le.ip1.and.lenkv(ip).ne.0)
              if(knext(k,lenkv(ip)).eq.k1) goto 2
              ip=ip+1
            end do
    2       continue

            ip0=ip0+1

            if(ip.le.ip1.and.lenkv(ip).ne.0) then  !swap here
              ie=lenkv(ip0)
              lenkv(ip0)=lenkv(ip)
              lenkv(ip)=ie
            end if
          end do

        end do  !loop over all nodes

c-------------------------------------------------------------------
c compact structure of non boundary nodes
c
c for elements we could theoretically compact all entries,
c but we want to reuse ilinkv also for the node pointer,
c and therefore we need one more entry for boundary nodes
c-------------------------------------------------------------------

        nfill = 0

        do k=1,nkn

          ip0=ilinkv(k)+1
          ip1=ilinkv(k+1)
          if( lenkv(ip1) .eq. 0 ) ip1 = ip1 - 1

          ie0 = lenkv(ip0)
          ie1 = lenkv(ip1)
          k0 = knext(k,ie0)
          k1 = kbhnd(k,ie1)
          if( k0 .ne. k1 ) ip1 = ip1 + 1        !boundary node

          ilinkv(k) = nfill
          do ip=ip0,ip1
            nfill = nfill + 1
            lenkv(nfill) = lenkv(ip)
          end do

        end do

        ilinkv(nkn+1) = nfill

c-------------------------------------------------------------------
c check structure
c-------------------------------------------------------------------

	call checklenk(nkn,ilinkv,lenkv,nen3v)

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

        return
   97   continue
        write(6,*) 'node: ',ipext(k),'  nkn: ',nkn
        write(6,*) 'error stop mklenk : internal error (2)'
        stop 'error stop mklenk : internal error (2)'
   98   continue
        write(6,*) n,nlkddi
        write(6,*) nkn,nel,2*nkn+nel
        stop 'error stop mklenk: nlkddi'
   99   continue
        !write(6,*) k,ilinkv(k),ip,ip1
        write(6,*) 'node: ',k,ipext(k)
        write(6,*) 'element: ',ie,ieext(ie)
        write(6,*) 'first entry: ',ilinkv(k)+1
        write(6,*) 'last entry: ',ip1
        write(6,*) 'actual pointer: ',ip
        write(6,*) 'error stop mklenk : internal error (1)'
        stop 'error stop mklenk : internal error (1)'
        end

c****************************************************************

        subroutine checklenk(nkn,ilinkv,lenkv,nen3v)

c checks structure of lenkv

	use link_structure

        implicit none

c arguments
        integer nkn
        integer ilinkv(nkn+1)
        integer lenkv(*)
	integer nen3v(3,*)
c local
	integer nbnd,nnull
	integer k,k0,k1,ie,ie0,ie1
	integer ip,ip0,ip1
	integer i
	integer ipp,ii
	integer kbhnd,knext,kthis
	logical berror

	integer ipext,ieext

	berror = .false.

        nbnd = 0        !total number of boundary nodes
        nnull = 0       !total number of 0 entries

c-------------------------------------------------------------------
c loop over nodes
c-------------------------------------------------------------------

        do k=1,nkn

          ip0=ilinkv(k)+1
          ip1=ilinkv(k+1)
          if( lenkv(ip1) .eq. 0 ) ip1 = ip1 - 1

          do ip=ip0,ip1
            ie = lenkv(ip)
            if( ie .eq. 0 ) then	!0 in index found
              write(6,*) 'Node (internal) k = ',k
              write(6,*) 'Node (external) k = ',ipext(k)
              write(6,*) k,ip0,ip1
              write(6,*) (lenkv(i),i=ip0,ip1)
              write(6,*) 'checklenk: internal lenkv (2)'
	      berror = .true.
            end if
          end do

          do ip=ip0+1,ip1
            ie0 = lenkv(ip-1)
            ie1 = lenkv(ip)
            k0 = kbhnd(k,ie0)
            k1 = knext(k,ie1)
            if( k0 .ne. k1 ) then	!something is wrong
              write(6,*) 'Node (internal) k = ',k
              write(6,*) 'Node (external) k = ',ipext(k)
              write(6,*) ip0,ip1,ip
              write(6,*) ie0,ie1,k0,k1
              write(6,*) ie0,(kthis(i,ie0),i=1,3)
              write(6,*) ie1,(kthis(i,ie1),i=1,3)
              write(6,*) (lenkv(i),i=ip0,ip1)
	      do ipp=ip0,ip1
		ie = lenkv(ipp)
		write(6,*) ie,(nen3v(ii,ie),ii=1,3)
	      end do
              write(6,*) 'checklenk: internal error lenkv (3)'
	      berror = .true.
            end if
          end do

          ie0 = lenkv(ip0)
          ie1 = lenkv(ip1)
          k0 = knext(k,ie0)
          k1 = kbhnd(k,ie1)
          if( k0 .ne. k1 ) nbnd = nbnd + 1

          if( lenkv(ilinkv(k+1)) .eq. 0 ) nnull = nnull + 1

        end do

	if( bverbose ) then
          write(6,*) 'checklenk: ',nnull,nbnd,nkn
	end if

	if( bstop .and. berror ) then
	  write(6,*) 'checklenk: errors in element structure'
	  stop 'error stop checklenk: internal errors'
	end if

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

        end

c****************************************************************
c****************************************************************
c****************************************************************

        subroutine mklenkii(nlkddi,nkn,nel,nen3v,ilinkv,lenkv,lenkiiv)

c sets up vector lenkiiv
c
c only array nen3v is needed, no aux array is needed
c
c ilinkv    pointer to links
c lenkv     link to element numbers
c
c number of links of node n : nl = ilinkv(n+1)-ilinkv(n)
c links of node n           : ( lenkv ( ilinkv(n)+i ), i=1,nl )

        implicit none

c arguments
        integer nlkddi
        integer nkn
        integer nel
        integer nen3v(3,nel)
        integer ilinkv(nkn+1)
        integer lenkv(*)
        integer lenkiiv(*)
c local
        integer ie,i,n,k,ii,ibase

c-------------------------------------------------------------------
c compute the vertec number for elements connected to node k
c-------------------------------------------------------------------

	do i=1,nlkddi
	  lenkiiv(i) = 0
	end do

        do k=1,nkn
	  n = ilinkv(k+1)-ilinkv(k)
	  ibase = ilinkv(k)
	  if( lenkv(ibase+n) .le. 0 ) n = n - 1
	  do i=1,n
	    ie = lenkv(ibase+i)
	    do ii=1,3
	      if( nen3v(ii,ie) == k ) exit
	    end do
	    if( ii > 3 ) goto 99
	    lenkiiv(ibase+i) = ii
	  end do
        end do

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

	return
   99	continue
	write(6,*) 'k,ie,n,ibase ',k,ie,n,ibase
	write(6,*) 'error stop mklenkii: internal error (1)'
	stop 'error stop mklenkii: internal error (1)'
	end

c****************************************************************
c****************************************************************
c****************************************************************

        subroutine mklink(nkn,ilinkv,lenkv,linkv)

c sets up vector with node links
c
c ilinkv and lenkv must have already been set up
c
c only array nen3v is needed, no aux array is needed
c
c ilinkv    pointer to links
c lenkv     link to element numbers
c linkv     link to node numbers

        implicit none

c arguments
        integer nkn
        integer ilinkv(nkn+1)
        integer lenkv(*)
        integer linkv(*)
c local
        integer ie,k
        integer ip,ip0,ip1
c functions
        integer knext,kbhnd

c-------------------------------------------------------------------
c loop over nodes
c-------------------------------------------------------------------

        do k=1,nkn

          ip0=ilinkv(k)+1
          ip1=ilinkv(k+1)
          if( lenkv(ip1) .eq. 0 ) ip1 = ip1 - 1

          do ip=ip0,ip1
            ie = lenkv(ip)
            linkv(ip) = knext(k,ie)
          end do

c         ----------------------------------------------------------
c         if boundary node insert last node
c         ----------------------------------------------------------

          ip=ilinkv(k+1)
          if( lenkv(ip) .eq. 0 ) then
            linkv(ip) = kbhnd(k,ie)
          end if

        end do

c-------------------------------------------------------------------
c check structure
c-------------------------------------------------------------------

	call checklink(nkn,ilinkv,linkv)

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

        end

c****************************************************************

        subroutine checklink(nkn,ilinkv,linkv)

c checks structure of lenkv

	use link_structure

        implicit none

c arguments
        integer nkn
        integer ilinkv(nkn+1)
        integer linkv(*)
c local
	integer k,k1,i
	integer ip,ip0,ip1
	integer ipk,ipk0,ipk1

	integer ipext

	k1 = 0				!compiler warnings
	ipk0 = 0
	ipk1 = 0

c-------------------------------------------------------------------
c loop over nodes
c-------------------------------------------------------------------

        do k=1,nkn

          ip0=ilinkv(k)+1
          ip1=ilinkv(k+1)
          if( linkv(ip1) .eq. 0 ) then	!0 in index found
            write(6,*) 'Node (internal) k = ',k
            write(6,*) 'Node (external) k = ',ipext(k)
            write(6,*) ip0,ip1
            write(6,*) (linkv(ip),ip=ip0,ip1)
            write(6,*) 'checklink: internal error (1)'
            if(bstop) stop 'error stop checklink: internal error (1)'
          end if

	  do ip=ip0,ip1
	    k1 = linkv(ip)
            ipk0=ilinkv(k1)+1
            ipk1=ilinkv(k1+1)
	    ipk = ipk0
	    do while( ipk .le. ipk1 .and. linkv(ipk) .ne. k )
	      ipk = ipk + 1
	    end do
	    if( ipk .gt. ipk1 ) then	!node not found
              write(6,*) 'Node (internal) k = ',k
              write(6,*) 'Node (external) k = ',ipext(k)
              write(6,*) ip0,ip1
              write(6,*) (linkv(i),i=ip0,ip1)
              write(6,*) k1,ipk0,ipk1
              write(6,*) (linkv(i),i=ipk0,ipk1)
              write(6,*) 'checklink: internal error (2)'
              if(bstop) stop 'error stop checklink: internal error (2)'
	    end if
	  end do
        end do

	if( bverbose ) then
          write(6,*) 'checklink: ',nkn
	end if

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

        end

c****************************************************************
c****************************************************************
c****************************************************************

        subroutine mkkant(nkn,ilinkv,lenkv,linkv,kantv)

c makes vector kantv

        implicit none

c arguments
        integer nkn
        integer ilinkv(nkn+1)
        integer lenkv(*)
        integer linkv(*)
        integer kantv(2,nkn)
c local
	integer k
	integer ip,ip0,ip1

        do k=1,nkn
          kantv(1,k)=0
          kantv(2,k)=0
        end do

        do k=1,nkn
          ip0=ilinkv(k)+1
          ip1=ilinkv(k+1)
          if( lenkv(ip1) .eq. 0 ) then		!boundary node
            kantv(1,k) = linkv(ip0)
            kantv(2,k) = linkv(ip1)
          end if
        end do

c-------------------------------------------------------------------
c check structure
c-------------------------------------------------------------------

	call checkkant(nkn,kantv)

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

        end

c****************************************************************

        subroutine checkkant(nkn,kantv)

c checks structure of kantv

	use link_structure

        implicit none

c arguments
        integer nkn
        integer kantv(2,nkn)
c local
	integer k,k1,k2
	integer nbnd,nint

	integer ipext

	nbnd = 0
	nint = 0

c-------------------------------------------------------------------
c loop over nodes
c-------------------------------------------------------------------

        do k=1,nkn
	  k1 = kantv(1,k)
	  k2 = kantv(2,k)
	  if( k1 .gt. 0 .and. k2 .gt. 0 ) then
	    nbnd = nbnd + 1
	    if( k .ne. kantv(2,k1) .or. k .ne. kantv(1,k2) ) then
              write(6,*) 'Node (internal) k = ',k
              write(6,*) 'Node (external) k = ',ipext(k)
	      write(6,*) 'k1,k2: ',k1,k2
	      write(6,*) 'backlink: ',kantv(2,k1),kantv(1,k2)
	      write(6,*) 'checkkant: structure of kantv (2)'
	      if(bstop) stop 'error stop checkkant: internal error (2)'
	    end if
	  else if( k1 .eq. 0 .and. k2 .eq. 0 ) then
	    nint = nint + 1
	  else
            write(6,*) 'Node (internal) k = ',k
            write(6,*) 'Node (external) k = ',ipext(k)
	    write(6,*) 'k1,k2: ',k1,k2
	    write(6,*) 'checkkant: structure of kantv (1)'
	    if(bstop) stop 'error stop checkkant: internal error (1)'
	  end if
        end do

	if( bverbose ) then
	  write(6,*) 'checkkant: ',nkn,nint,nbnd
	end if

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

        end

c****************************************************************
c****************************************************************
c****************************************************************

        subroutine mkielt(nkn,nel,ilinkv,lenkv,linkv,ieltv)

c makes vector ieltv (without open boundary nodes)

        implicit none

c arguments
        integer nkn,nel
        integer ilinkv(nkn+1)
        integer lenkv(*)
        integer linkv(*)
        integer ieltv(3,nel)
c local
	integer k,ie,ii
	integer ip,ip0,ip1
	integer inext

c-------------------------------------------------------------------
c initialize
c-------------------------------------------------------------------

        do ie=1,nel
          do ii=1,3
            ieltv(ii,ie) = 0
          end do
        end do

c-------------------------------------------------------------------
c loop over links
c-------------------------------------------------------------------

        do k=1,nkn
          ip0=ilinkv(k)+1
          ip1=ilinkv(k+1) - 1

          do ip=ip0,ip1
            ie=lenkv(ip)
            ieltv(inext(k,ie),ie)=lenkv(ip+1)
          end do

c	  -------------------------------------------------------------------
c	  last element
c	  -------------------------------------------------------------------

          ie=lenkv(ip1+1)
          if(ie.gt.0) then                              !is internal node
            ieltv(inext(k,ie),ie)=lenkv(ip0)
          end if

        end do

c-------------------------------------------------------------------
c check structure
c-------------------------------------------------------------------

	call checkielt(nel,ieltv)

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

	end

c****************************************************************

        subroutine checkielt(nel,ieltv)

c checks structure of ieltv

	use link_structure

        implicit none

c arguments
        integer nel
        integer ieltv(3,nel)
c local
	integer k,ie,ii
	integer kn,inn,ien,ienn
        integer nbnd,nobnd,nintern
	integer inext,knext,kthis

c-------------------------------------------------------------------
c initialize
c-------------------------------------------------------------------

        nbnd = 0
        nobnd = 0
        nintern = 0

c-------------------------------------------------------------------
c loop over elements
c-------------------------------------------------------------------

        do ie=1,nel
          do ii=1,3
            ien = ieltv(ii,ie)
            if( ien .gt. 0 ) then
            	nintern = nintern + 1
                if( ien .gt. nel ) goto 99
                k = kthis(ii,ie)
                kn = knext(k,ie)
                inn = inext(kn,ien)
                ienn = ieltv(inn,ien)
                if( ie .ne. ienn ) goto 98
            else if( ien .eq. 0 ) then
                nbnd = nbnd + 1
            else if( ien .eq. -1 ) then
                nobnd = nobnd + 1
            else
                goto 99
            end if
          end do
        end do

	if( bverbose ) then
          write(6,*) 'checkielt is ok'
          write(6,*) '  internal sides =      ',nintern
          write(6,*) '  boundary sides =      ',nbnd
          write(6,*) '  open boundary sides = ',nobnd
          write(6,*) '  total sides =         ',nintern+nbnd+nobnd
	end if

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

        return
   98   continue
        write(6,*) 'Element (internal) ie = ',ie
        write(6,*) 'ii,ien,nel: ',ii,ien,nel
        write(6,*) 'k,kn,inn,ienn: ',k,kn,inn,ienn
        write(6,*) 'nen3v: ',ie,(kthis(ii,ie),ii=1,3)
        write(6,*) 'nen3v: ',ien,(kthis(ii,ien),ii=1,3)
        write(6,*) 'ieltv: ',ie,(ieltv(ii,ie),ii=1,3)
        write(6,*) 'ieltv: ',ien,(ieltv(ii,ien),ii=1,3)
	write(6,*) 'checkielt: corrupt data structure of ieltv (1)'
        if(bstop) stop 'error stop checkielt: internal error (1)'
   99   continue
        write(6,*) 'Element (internal) ie = ',ie
        write(6,*) 'ii,ien,nel: ',ii,ien,nel
	write(6,*) 'checkielt: corrupt data structure of ieltv (2)'
        if(bstop) stop 'error stop checkielt: internal error (2)'
	end

c****************************************************************

        subroutine update_ielt(nel,ibound,ieltv)

c updates vector ieltv with open boundary nodes

        implicit none

c arguments
        integer nel
        integer ibound(*)	! >0 => open boundary node
        integer ieltv(3,nel)
c local
	integer k,ie,ii,i
	integer ip,ip0,ip1
	integer knext,ibhnd,kthis

c-------------------------------------------------------------------
c loop over elements
c-------------------------------------------------------------------

        do ie=1,nel
          do ii=1,3
	    k = kthis(ii,ie)
	    if( ibound(k) .gt. 0 .and. ibound(knext(k,ie)) .gt. 0 ) then
	      i = ibhnd(k,ie)
              ieltv(i,ie) = -1
	    end if
          end do
        end do

c-------------------------------------------------------------------
c check structure
c-------------------------------------------------------------------

	call checkielt(nel,ieltv)

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

	end

c****************************************************************
c****************************************************************
c****************************************************************

        subroutine mkdxy(nkn,dxv,dyv)

c initializes dxv,dyv

        implicit none

c arguments
        integer nkn
	real dxv(nkn),dyv(nkn)
c local
	integer k,ie,ii,i
	integer ip,ip0,ip1
	integer knext,ibhnd,kthis

c-------------------------------------------------------------------
c loop over nodes
c------------------------------------------------------------------

        do k=1,nkn
	  dxv(k) = 0.
	  dyv(k) = 0.
        end do

c-------------------------------------------------------------------
c end of routine
c-------------------------------------------------------------------

	end

c****************************************************************
c****************************************************************
c****************************************************************

