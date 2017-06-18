//
//  BRCMediaDownloader.swift
//  iBurn
//
//  Created by Chris Ballinger on 8/8/16.
//  Copyright © 2016 Burning Man Earth. All rights reserved.
//

import Foundation
import YapDatabase
import CocoaLumberjack

@objc
public enum BRCMediaDownloadType: Int
{
    case unknown = 0
    case audio
    case image
}

open class BRCMediaDownloader: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    
    let viewName: String
    let connection: YapDatabaseConnection
    var session: Foundation.URLSession!
    
    let downloadType: BRCMediaDownloadType
    open let backgroundSessionIdentifier: String
    var observer: NSObjectProtocol?
    open var backgroundCompletion: (()->())?
    let delegateQueue = OperationQueue()
    var backgroundTask: UIBackgroundTaskIdentifier
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    public init(connection: YapDatabaseConnection, viewName: String, downloadType: BRCMediaDownloadType) {
        self.downloadType = downloadType
        self.connection = connection
        self.viewName = viewName
        let backgroundSessionIdentifier = "BRCMediaDownloaderSession" + viewName
        self.backgroundSessionIdentifier = backgroundSessionIdentifier
        let config = URLSessionConfiguration.background(withIdentifier: backgroundSessionIdentifier)
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: backgroundSessionIdentifier, expirationHandler: { 
            NSLog("%@ task expired", backgroundSessionIdentifier)
        })
        super.init()
        self.session = Foundation.URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        observer = NotificationCenter.default.addObserver(forName: NSNotification.Name.BRCDatabaseExtensionRegistered, object: BRCDatabaseManager.shared, queue: OperationQueue.main) { (notification) in
            if let extensionName = notification.userInfo?["extensionName"] as? String {
                if extensionName == self.viewName {
                    NSLog("BRCMediaDownloader databaseExtensionRegistered: %@", extensionName)
                    self.downloadUncachedMedia()
                }
            }
        }
    }
    
    open static func downloadPath() -> String {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
        let folderName = "MediaFiles"
        let path = documentsPath.appendingPathComponent(folderName)
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            } catch {}
        }
        return path
    }
    
    open static func localMediaURL(_ fileName: String) -> URL {
        let downloadPath = self.downloadPath() as NSString
        let path = downloadPath.appendingPathComponent(fileName)
        let url = URL(fileURLWithPath: path)
        return url
    }
    
    open static func fileName(_ art: BRCArtObject, type: BRCMediaDownloadType) -> String {
        let fileType = extensionForDownloadType(type)
        let fileName = (art.uniqueID as NSString).appendingPathExtension(fileType)!
        return fileName
    }
    
    fileprivate static func extensionForDownloadType(_ type: BRCMediaDownloadType) -> String {
        switch type {
        case .image:
            return "jpg"
        case .audio:
            return "mp3"
        default:
            return ""
        }
    }
    
    /** This will cache un-downloaded media */
    open func downloadUncachedMedia() {
        connection.asyncRead { (transaction) in
            guard let viewTransaction = transaction.ext(self.viewName) as? YapDatabaseViewTransaction else {
                return
            }
            var art: [URL: BRCArtObject] = [:]
            viewTransaction.enumerateGroups({ (group, stop) -> Void in
                viewTransaction.enumerateKeysAndObjects(inGroup: group, with: [], using: { (collection: String, key: String, object: Any, index: UInt, stop: UnsafeMutablePointer<ObjCBool>) in
                    if let dataObject = object as? BRCArtObject {
                        
                        // Only add files that haven't been downloaded
                        var remoteURL: URL? = nil
                        var localURL: URL? = nil
                        switch self.downloadType {
                        case .image:
                            remoteURL = dataObject.remoteThumbnailURL
                            localURL = dataObject.localThumbnailURL
                            break
                        case .audio:
                            remoteURL = dataObject.remoteAudioURL
                            localURL = dataObject.localAudioURL
                            break
                        default:
                            break
                        }
                        
                        if localURL == nil && remoteURL == nil {
                            return
                        }
                        
                        if remoteURL != nil && localURL == nil {
                            DDLogInfo("Downloading media for \(String(describing: remoteURL))")
                            art[remoteURL!] = dataObject
                        } else {
                            //NSLog("Already downloaded media for %@", remoteURL!)
                        }
                    }
                })
            })
            self.session.getTasksWithCompletionHandler({ (_, _, downloads) in
                // Remove things already being downloaded
                for download in downloads {
                    DDLogWarn("canceling existing download: \(download)")
                    download.cancel()
                }
                self.downloadFiles(Array(art.values))
            })
        }
    }
    
    fileprivate func remoteURL(_ file: BRCArtObject) -> URL? {
        switch downloadType {
        case .audio:
            return file.remoteAudioURL
        case .image:
            return file.remoteThumbnailURL
        case .unknown:
            return nil
        }
    }
    
    fileprivate func downloadFiles(_ files: [BRCArtObject]) {
        for file in files {
            guard let remoteURL = self.remoteURL(file) else {
                DDLogError("No remote URL for file \(file)")
                return
            }
            let task = self.session.downloadTask(with: remoteURL)
            let fileName = type(of: self).fileName(file, type: downloadType)
            task.taskDescription = fileName
            DDLogInfo("Downloading file: \(String(describing: remoteURL))")
            task.resume()
        }
    }
    
    //MARK: NSURLSessionDelegate
    open func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let backgroundCompletion = backgroundCompletion {
            backgroundCompletion()
        }
        backgroundCompletion = nil
    }
    
    //MARK: NSURLSessionDownloadDelegate
    
    open func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let fileName = downloadTask.taskDescription else {
            DDLogError("taskDescription is nil!")
            return
        }
        let destURL = type(of: self).localMediaURL(fileName)
        do {
            try FileManager.default.moveItem(at: location, to: destURL)
            try (destURL as NSURL).setResourceValue(true, forKey: URLResourceKey.isExcludedFromBackupKey)
        } catch let error as NSError {
            DDLogError("Error moving file: \(error)")
            return
        }
        DDLogInfo("Media file cached: \(destURL)")
        self.session.getTasksWithCompletionHandler({ (_, _, downloads) in
            if downloads.count == 0 {
                if self.backgroundTask != UIBackgroundTaskInvalid {
                    UIApplication.shared.endBackgroundTask(self.backgroundTask)
                    self.backgroundTask = UIBackgroundTaskInvalid
                }
                
            }
        })
    }
    
}