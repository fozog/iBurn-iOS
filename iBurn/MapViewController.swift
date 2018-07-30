//
//  MapViewController.swift
//  iBurn
//
//  Created by Chris Ballinger on 6/14/17.
//  Copyright © 2017 Burning Man Earth. All rights reserved.
//

import UIKit
import YapDatabase
import CoreLocation
import BButton
import CocoaLumberjack
import MapboxDirections
import MapboxCoreNavigation
import MapboxNavigation

public class MapViewController: BaseMapViewController {
    let readConnection: YapDatabaseConnection
    let writeConnection: YapDatabaseConnection
    /// This contains the buttons for finding the nearest POIs e.g. bathrooms
    let sidebarButtons: SidebarButtonsView
    let geocoder: BRCGeocoder
    var userAnnotations: [BRCUserMapPoint] = []
    let search: SearchDisplayManager
    
    public override init() {
        readConnection = BRCDatabaseManager.shared.readConnection
        writeConnection = BRCDatabaseManager.shared.readWriteConnection
        sidebarButtons = SidebarButtonsView()
        geocoder = BRCGeocoder.shared
        search = SearchDisplayManager(viewName: BRCDatabaseManager.shared.searchCampsView)
        super.init()
        title = NSLocalizedString("Map", comment: "title for map view")
        setupUserGuide()
        setupSearch(search)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Lifecycle
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        // TODO: make sidebar buttons work
        setupSidebarButtons()
    }
    
    private func setupSidebarButtons() {
        view.addSubview(sidebarButtons)
        let bottom = sidebarButtons.autoPinEdge(toSuperviewMargin: .bottom)
        bottom.constant = -50
        sidebarButtons.autoPinEdge(toSuperviewMargin: .left)
        sidebarButtons.autoSetDimensions(to: CGSize(width: 40, height: 250))
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadUserAnnotations()
        geocodeNavigationBar()
    }
    
    // MARK: - User Interaction
    
    private func setupSearch(_ search: SearchDisplayManager) {
        search.tableViewAdapter.delegate = self
    }
    
    // MARK: - Annotations
    
    private func setupUserGuide() {
        sidebarButtons.findNearestAction = { [weak self] mapPointType, sender in
            guard let location = self?.mapView.userLocation?.location else {
                DDLogWarn("User location not found!")
                return
            }
            self?.readConnection.read { transaction in
                if let point = UserGuidance.findNearest(userLocation: location, mapPointType: mapPointType, transaction: transaction) {
                    DDLogInfo("Found closest point: \(point)")
                    self?.showDirections(from: location, to: point.waypoint)
                } else if mapPointType == .userBike || mapPointType == .userHome {
                    // If we can't find your bike or home, let's make a new one
                   self?.addUserMapPoint(type: mapPointType)
                }
            }
        }
        sidebarButtons.placePinAction = { [weak self] sender in
            self?.addUserMapPoint(type: .userStar)
        }
        mapViewDelegate.saveMapPoint = { [weak self] mapPoint in
            self?.writeConnection.readWrite { transaction in
                mapPoint.save(with: transaction, metadata: nil)
            }
            self?.mapViewDelegate.editingAnnotation = nil
            self?.mapView.removeAnnotation(mapPoint)
            DDLogInfo("Saved user annotation: \(mapPoint)")
            self?.reloadUserAnnotations()
        }
        sidebarButtons.searchAction = { [weak self] sender in
            guard let strongSelf = self else { return }
            strongSelf.present(strongSelf.search.searchController, animated: true, completion: nil)
        }
    }
    
    private func reloadUserAnnotations() {
        mapView.removeAnnotations(userAnnotations)
        userAnnotations = []
        readConnection.asyncRead({ transaction in
            transaction.enumerateKeysAndObjects(inCollection: BRCUserMapPoint.yapCollection, using: { (key, object, stop) in
                if let mapPoint = object as? BRCUserMapPoint {
                    self.userAnnotations.append(mapPoint)
                }
            })
        }, completionBlock: {
            self.mapView.addAnnotations(self.userAnnotations)
        })
    }
    
    private func addUserMapPoint(type: BRCMapPointType) {
        var coordinate = BRCLocations.blackRockCityCenter
        if let userLocation = self.mapView.userLocation?.location {
            coordinate = userLocation.coordinate
        }
        // don't drop user-location pins if youre not at BM
        if !BRCLocations.burningManRegion.contains(coordinate) ||
            !CLLocationCoordinate2DIsValid(coordinate) {
            coordinate = BRCLocations.blackRockCityCenter
        }
        let mapPoint = BRCUserMapPoint(title: NSLocalizedString("Favorite", comment:"favorite marked on map"), coordinate: coordinate, type: type)
        if let existingMapPoint = mapViewDelegate.editingAnnotation {
            mapView.removeAnnotation(existingMapPoint)
        }
        mapViewDelegate.editingAnnotation = mapPoint
        mapView.addAnnotation(mapPoint)
    }
    
    private func showDirections(from: CLLocation, to destination: Waypoint) {
        // TODO: Add some sort of routing. Default Mapbox routing doesn't work.
//        let origin = Waypoint(coordinate: from.coordinate, name: "Start")
//
//        let options = NavigationRouteOptions(waypoints: [origin, destination])
//
//        Directions.shared.calculate(options) { [weak self] (waypoints, routes, error) in
//            guard let route = routes?.first else { return }
//
//            let viewController = NavigationViewController(for: route)
//            self?.present(viewController, animated: true, completion: nil)
//        }
    }
}

extension MapViewController: YapTableViewAdapterDelegate {
    public func didSelectObject(_ adapter: YapTableViewAdapter, object: DataObject, in tableView: UITableView, at indexPath: IndexPath) {
        let detail = BRCDetailViewController(dataObject: object.object)
        self.navigationController?.pushViewController(detail, animated: false)
        search.searchController.dismiss(animated: true, completion: nil)
    }
}

private extension BRCMapPoint {
    var waypoint: Waypoint {
        return Waypoint(coordinate: coordinate, name: title)
    }
}
